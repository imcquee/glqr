import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Error type for QR code generation
pub type GenerateError {
  EmptyValue(String)
  InvalidVersion(Int)
  ProvidedValueExceedsCapacity(value_length: Int, capacity: Int)
  InvalidNumericEncoding(String)
  InvalidAlphanumericEncoding(String)
  InvalidUtf8Encoding(String)
  InvalidRemainingBits(String)
}

/// Config for QR code
/// - `value`: The string value to encode in the QR code
/// - `error_correction`: The error correction level to use (L, M, Q, H) M is the default
/// - `min_version`: The minimum QR code version to use (1-40) 1 is the default
pub type QrConfig {
  QrConfig(
    value: String,
    error_correction: ErrorCorrectionLevel,
    min_version: Int,
  )
}

/// Error correction levels for QR codes
/// - L: Recovers 7% of data
/// - M: Recovers 15% of data (default)
/// - Q: Recovers 25% of data
/// - H: Recovers 30% of data
/// https://www.thonky.com/qr-code-tutorial/data-encoding (Step 1)
pub type ErrorCorrectionLevel {
  L
  M
  Q
  H
}

/// QR code version (1-40) which determines the size of the QR code and the amount of data it can hold
/// Version 1 is 21x21
/// Version 40 is 177x177
/// https://www.thonky.com/qr-code-tutorial/character-capacities
pub opaque type Version {
  Version(Int)
}

/// Generated QR code containing the module data
/// Use `to_printable`, `to_svg`, or `to_bits` to convert to different formats
pub opaque type Qr {
  Qr(size: Int, rows: List(List(Bool)))
}

type ECInfo {
  ECInfo(
    data_codewords: Int,
    ec_codewords_per_block: Int,
    group1_blocks: Int,
    group1_block_size: Int,
    group2_blocks: Int,
    group2_block_size: Int,
  )
}

type EncodingMode {
  Numeric
  Alphanumeric
  UTF8
}

type Matrix {
  Matrix(
    size: Int,
    modules: Dict(#(Int, Int), Bool),
    function_modules: Dict(#(Int, Int), Nil),
  )
}

/// Create a new QR code config with the provided value and default settings for error correction and minimum version
/// Default error correction level is M (15% recovery)
/// Default minimum version is 1 (21x21)
pub fn new(value: String) -> QrConfig {
  QrConfig(value: value, error_correction: M, min_version: 1)
}

/// Set the error correction level for the QR code config
/// - L: Recovers 7% of data
/// - M: Recovers 15% of data (default)
/// - Q: Recovers 25% of data
/// - H: Recovers 30% of data
pub fn error_correction(
  config: QrConfig,
  level: ErrorCorrectionLevel,
) -> QrConfig {
  QrConfig(..config, error_correction: level)
}

/// Set the minimum version for the QR code config (1-40)
/// Version 1 is 21x21
/// Version 40 is 177x177
pub fn min_version(config: QrConfig, version: Int) -> QrConfig {
  QrConfig(..config, min_version: version)
}

/// Generate a QR code based on the provided config
/// Returns a Qr that can be converted to different formats using `to_printable`, `to_svg`, or `to_bits`
pub fn generate(config: QrConfig) -> Result(Qr, GenerateError) {
  let value = config.value
  case value {
    "" -> Error(EmptyValue("Provided value cannot be empty"))
    _ -> {
      let #(mode, size) = detect(bit_array.from_string(value), Numeric, 0)
      let level = config.error_correction
      let min = config.min_version

      use <- guard_version(min)
      // https://www.thonky.com/qr-code-tutorial/data-encoding (Step 2) Determine smallest version
      use version <- result.try(find_version(size, mode, min, level))

      use enc <- result.try(encode(value, mode))
      let mode_indicator = mode_indicator(mode)
      let char_count_indicator = character_count_indicator(mode, size, version)
      let bit_count = data_bit_count(value, size, mode, version)
      let terminator = terminator_bit_count(value, size, mode, version, level)
      let term_padding_bits =
        terminator_padding_bit_count(bit_count + terminator)
      let required_bits = required_bits(version, level)
      let encoding_bits_with_terminator =
        bit_count + terminator + term_padding_bits
      use enc_padding <- result.try(encoding_padding_bytes(
        required_bits - encoding_bits_with_terminator,
      ))

      // https://www.thonky.com/qr-code-tutorial/data-encoding (Step 3-4) Full encoding + padding
      let data_bits = <<
        mode_indicator:bits,
        char_count_indicator:bits,
        enc:bits,
        0:size(terminator),
        0:size(term_padding_bits),
        enc_padding:bits,
      >>

      let data_bytes = bits_to_bytes(data_bits)
      let ec_info = ec_info(version, level)
      // https://www.thonky.com/qr-code-tutorial/error-correction-coding
      let #(data_blocks, ec_blocks) = split_into_blocks(data_bytes, ec_info)
      // https://www.thonky.com/qr-code-tutorial/structure-final-message (Step 2-4)
      let interleaved = interleave_blocks(data_blocks, ec_blocks, version)
      let dimensions = version_size(version)
      // https://www.thonky.com/qr-code-tutorial/module-placement-matrix
      // https://www.thonky.com/qr-code-tutorial/data-masking 
      let matrix =
        matrix_new(dimensions)
        |> place_function_patterns(version)
        |> reserve_format_areas()
        |> reserve_version_areas(version)
        |> place_data_bits(interleaved)

      Ok(find_best_mask_and_render(matrix, version, level))
    }
  }
}

fn guard_version(
  version: Int,
  next: fn() -> Result(Qr, GenerateError),
) -> Result(Qr, GenerateError) {
  case version {
    v if 1 <= v && v <= 40 -> next()
    _ -> Error(InvalidVersion(version))
  }
}

/// Convert the QR code into a printable string representation using Unicode block characters
/// You must use io.println to print this rather than echo as echo will preserve the newlines
pub fn to_printable(qr: Qr) -> String {
  let Qr(size, rows) = qr
  let quiet_zone = 4
  let total = size + quiet_zone * 2
  // Build rows with quiet zone padding
  let quiet_row = string.repeat(" ", total)
  let quiet_rows = string.repeat(quiet_row <> "\n", quiet_zone / 2)
  let side_padding = string.repeat(" ", quiet_zone)
  let data_rows = printable_row_pairs(rows, side_padding, [])
  // Trim trailing newline to avoid extra empty line at end
  let result = quiet_rows <> string.join(data_rows, "\n") <> "\n" <> quiet_rows
  string.drop_end(result, 1)
}

fn printable_row_pairs(
  rows: List(List(Bool)),
  padding: String,
  acc: List(String),
) -> List(String) {
  case rows {
    [top, bottom, ..rest] -> {
      let row_str = padding <> render_row_pair(top, bottom, "") <> padding
      printable_row_pairs(rest, padding, [row_str, ..acc])
    }
    [top] -> {
      let row_str = padding <> render_row_pair(top, [], "") <> padding
      list.reverse([row_str, ..acc])
    }
    [] -> list.reverse(acc)
  }
}

fn render_row_pair(top: List(Bool), bottom: List(Bool), acc: String) -> String {
  case top, bottom {
    [t, ..top_rest], [b, ..bottom_rest] -> {
      let char = case t, b {
        True, True -> "█"
        True, False -> "▀"
        False, True -> "▄"
        False, False -> " "
      }
      render_row_pair(top_rest, bottom_rest, acc <> char)
    }
    [t, ..top_rest], [] -> {
      let char = case t {
        True -> "▀"
        False -> " "
      }
      render_row_pair(top_rest, [], acc <> char)
    }
    [], _ -> acc
  }
}

/// Convert the QR code into an SVG string representation
pub fn to_svg(qr: Qr) -> String {
  let Qr(size, rows) = qr
  let quiet_zone = 4
  let total = size + quiet_zone * 2
  let rects = svg_rects_from_rows(rows, quiet_zone, 0, [])
  let total_str = int.to_string(total)
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 "
  <> total_str
  <> " "
  <> total_str
  <> "\" shape-rendering=\"crispEdges\">\n<rect width=\""
  <> total_str
  <> "\" height=\""
  <> total_str
  <> "\" fill=\"white\"/>\n<g fill=\"black\">\n"
  <> string.join(rects, "\n")
  <> "\n</g>\n</svg>"
}

/// Convert the QR code into a tuple of (size, bits) where size is the width/height
/// Each bit represents a module: 1 = Dark, 0 = Light
/// To access module at (row, col): bit index = row * size + col
pub fn to_bits(qr: Qr) -> #(Int, BitArray) {
  let Qr(size, rows) = qr
  let bits =
    list.fold(rows, <<>>, fn(acc, row) {
      list.fold(row, acc, fn(bits, cell) {
        case cell {
          True -> <<bits:bits, 1:1>>
          False -> <<bits:bits, 0:1>>
        }
      })
    })
  #(size, bits)
}

fn svg_rects_from_rows(
  rows: List(List(Bool)),
  quiet_zone: Int,
  row_idx: Int,
  acc: List(String),
) -> List(String) {
  case rows {
    [row, ..rest] -> {
      let row_rects = svg_row_rects(row, quiet_zone, row_idx, 0, acc)
      svg_rects_from_rows(rest, quiet_zone, row_idx + 1, row_rects)
    }
    [] -> list.reverse(acc)
  }
}

fn svg_row_rects(
  row: List(Bool),
  quiet_zone: Int,
  row_idx: Int,
  col_idx: Int,
  acc: List(String),
) -> List(String) {
  case row {
    [True, ..rest] -> {
      let rect =
        "<rect x=\""
        <> int.to_string(col_idx + quiet_zone)
        <> "\" y=\""
        <> int.to_string(row_idx + quiet_zone)
        <> "\" width=\"1\" height=\"1\"/>"
      svg_row_rects(rest, quiet_zone, row_idx, col_idx + 1, [rect, ..acc])
    }
    [False, ..rest] ->
      svg_row_rects(rest, quiet_zone, row_idx, col_idx + 1, acc)
    [] -> acc
  }
}

fn detect(
  bytes: BitArray,
  mode: EncodingMode,
  count: Int,
) -> #(EncodingMode, Int) {
  case bytes {
    <<byte, rest:bytes>> -> {
      let #(new_mode, new_count) = case byte {
        // 0-9
        b if b >= 48 && b <= 57 -> #(mode, count + 1)
        // A-Z
        b if b >= 65 && b <= 90 -> #(
          case mode {
            UTF8 -> UTF8
            _ -> Alphanumeric
          },
          count + 1,
        )
        // Space, $, %, *, +, -, ., /, :
        32 | 36 | 37 | 42 | 43 | 45 | 46 | 47 | 58 -> #(
          case mode {
            UTF8 -> UTF8
            _ -> Alphanumeric
          },
          count + 1,
        )
        // Anything else is UTF8
        _ -> #(UTF8, count + 1)
      }
      detect(rest, new_mode, new_count)
    }
    _ -> #(mode, count)
  }
}

fn encode(value: String, mode: EncodingMode) -> Result(BitArray, GenerateError) {
  let bytes = bit_array.from_string(value)
  case mode {
    Numeric -> encode_numeric(bytes, <<>>)
    Alphanumeric -> encode_alphanumeric(bytes, <<>>)
    UTF8 -> Ok(bytes)
  }
}

fn encode_numeric(
  bytes: BitArray,
  acc: BitArray,
) -> Result(BitArray, GenerateError) {
  case bytes {
    <<d1, d2, d3, rest:bytes>> -> {
      let num = { d1 - 48 } * 100 + { d2 - 48 } * 10 + { d3 - 48 }
      encode_numeric(rest, <<acc:bits, num:size(10)>>)
    }
    <<d1, d2>> -> {
      let num = { d1 - 48 } * 10 + { d2 - 48 }
      Ok(<<acc:bits, num:size(7)>>)
    }
    <<d1>> -> {
      let num = d1 - 48
      Ok(<<acc:bits, num:size(4)>>)
    }
    <<>> -> Ok(acc)
    _ -> Error(InvalidNumericEncoding("Invalid numeric encoding"))
  }
}

fn encode_alphanumeric(
  bytes: BitArray,
  acc: BitArray,
) -> Result(BitArray, GenerateError) {
  case bytes {
    <<b1, b2, rest:bytes>> -> {
      let v1 = alpha_value_byte(b1)
      let v2 = alpha_value_byte(b2)
      let combined = v1 * 45 + v2
      encode_alphanumeric(rest, <<acc:bits, combined:size(11)>>)
    }
    <<b1>> -> {
      let v = alpha_value_byte(b1)
      Ok(<<acc:bits, v:size(6)>>)
    }
    <<>> -> Ok(acc)
    _ -> Error(InvalidAlphanumericEncoding("Invalid alphanumeric encoding"))
  }
}

fn alpha_value_byte(byte: Int) -> Int {
  case byte {
    b if b >= 48 && b <= 57 -> b - 48
    b if b >= 65 && b <= 90 -> b - 65 + 10
    32 -> 36
    36 -> 37
    37 -> 38
    42 -> 39
    43 -> 40
    45 -> 41
    46 -> 42
    47 -> 43
    58 -> 44
    _ -> 0
  }
}

fn mode_indicator(mode: EncodingMode) -> BitArray {
  case mode {
    Numeric -> <<1:size(4)>>
    Alphanumeric -> <<2:size(4)>>
    UTF8 -> <<4:size(4)>>
  }
}

fn character_indicator_size(mode: EncodingMode, version: Version) -> Int {
  let Version(v) = version
  case mode {
    Numeric ->
      case v {
        x if x <= 9 -> 10
        x if x <= 26 -> 12
        _ -> 14
      }
    Alphanumeric ->
      case v {
        x if x <= 9 -> 9
        x if x <= 26 -> 11
        _ -> 13
      }
    UTF8 ->
      case v {
        x if x <= 9 -> 8
        _ -> 16
      }
  }
}

fn character_count_indicator(
  mode: EncodingMode,
  count: Int,
  version: Version,
) -> BitArray {
  let bits = character_indicator_size(mode, version)
  <<count:size(bits)>>
}

fn required_bits(version: Version, level: ErrorCorrectionLevel) -> Int {
  let ec_info = ec_info(version, level)
  ec_info.data_codewords * 8
}

fn find_version(
  count: Int,
  mode: EncodingMode,
  min_v: Int,
  level: ErrorCorrectionLevel,
) -> Result(Version, GenerateError) {
  let version_result = case mode {
    Numeric -> find_version_numeric(count, level)
    Alphanumeric -> find_version_alphanumeric(count, level)
    UTF8 -> find_version_utf8(count, level)
  }
  // Apply min_version constraint
  case version_result {
    Ok(Version(v)) if v < min_v -> Ok(Version(min_v))
    result -> result
  }
}

fn find_version_numeric(
  count: Int,
  level: ErrorCorrectionLevel,
) -> Result(Version, GenerateError) {
  case level {
    L ->
      case count {
        c if c <= 41 -> Ok(Version(1))
        c if c <= 77 -> Ok(Version(2))
        c if c <= 127 -> Ok(Version(3))
        c if c <= 187 -> Ok(Version(4))
        c if c <= 255 -> Ok(Version(5))
        c if c <= 322 -> Ok(Version(6))
        c if c <= 370 -> Ok(Version(7))
        c if c <= 461 -> Ok(Version(8))
        c if c <= 552 -> Ok(Version(9))
        c if c <= 652 -> Ok(Version(10))
        c if c <= 772 -> Ok(Version(11))
        c if c <= 883 -> Ok(Version(12))
        c if c <= 1022 -> Ok(Version(13))
        c if c <= 1101 -> Ok(Version(14))
        c if c <= 1250 -> Ok(Version(15))
        c if c <= 1408 -> Ok(Version(16))
        c if c <= 1548 -> Ok(Version(17))
        c if c <= 1725 -> Ok(Version(18))
        c if c <= 1903 -> Ok(Version(19))
        c if c <= 2061 -> Ok(Version(20))
        c if c <= 2232 -> Ok(Version(21))
        c if c <= 2409 -> Ok(Version(22))
        c if c <= 2620 -> Ok(Version(23))
        c if c <= 2812 -> Ok(Version(24))
        c if c <= 3057 -> Ok(Version(25))
        c if c <= 3283 -> Ok(Version(26))
        c if c <= 3517 -> Ok(Version(27))
        c if c <= 3669 -> Ok(Version(28))
        c if c <= 3909 -> Ok(Version(29))
        c if c <= 4158 -> Ok(Version(30))
        c if c <= 4417 -> Ok(Version(31))
        c if c <= 4686 -> Ok(Version(32))
        c if c <= 4965 -> Ok(Version(33))
        c if c <= 5253 -> Ok(Version(34))
        c if c <= 5529 -> Ok(Version(35))
        c if c <= 5836 -> Ok(Version(36))
        c if c <= 6153 -> Ok(Version(37))
        c if c <= 6479 -> Ok(Version(38))
        c if c <= 6743 -> Ok(Version(39))
        c if c <= 7089 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 7089,
          ))
      }
    M ->
      case count {
        c if c <= 34 -> Ok(Version(1))
        c if c <= 63 -> Ok(Version(2))
        c if c <= 101 -> Ok(Version(3))
        c if c <= 149 -> Ok(Version(4))
        c if c <= 202 -> Ok(Version(5))
        c if c <= 255 -> Ok(Version(6))
        c if c <= 293 -> Ok(Version(7))
        c if c <= 365 -> Ok(Version(8))
        c if c <= 432 -> Ok(Version(9))
        c if c <= 513 -> Ok(Version(10))
        c if c <= 604 -> Ok(Version(11))
        c if c <= 691 -> Ok(Version(12))
        c if c <= 796 -> Ok(Version(13))
        c if c <= 871 -> Ok(Version(14))
        c if c <= 991 -> Ok(Version(15))
        c if c <= 1082 -> Ok(Version(16))
        c if c <= 1212 -> Ok(Version(17))
        c if c <= 1346 -> Ok(Version(18))
        c if c <= 1500 -> Ok(Version(19))
        c if c <= 1600 -> Ok(Version(20))
        c if c <= 1708 -> Ok(Version(21))
        c if c <= 1872 -> Ok(Version(22))
        c if c <= 2059 -> Ok(Version(23))
        c if c <= 2188 -> Ok(Version(24))
        c if c <= 2395 -> Ok(Version(25))
        c if c <= 2544 -> Ok(Version(26))
        c if c <= 2701 -> Ok(Version(27))
        c if c <= 2857 -> Ok(Version(28))
        c if c <= 3035 -> Ok(Version(29))
        c if c <= 3289 -> Ok(Version(30))
        c if c <= 3486 -> Ok(Version(31))
        c if c <= 3693 -> Ok(Version(32))
        c if c <= 3909 -> Ok(Version(33))
        c if c <= 4134 -> Ok(Version(34))
        c if c <= 4343 -> Ok(Version(35))
        c if c <= 4588 -> Ok(Version(36))
        c if c <= 4775 -> Ok(Version(37))
        c if c <= 5039 -> Ok(Version(38))
        c if c <= 5313 -> Ok(Version(39))
        c if c <= 5596 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 5596,
          ))
      }
    Q ->
      case count {
        c if c <= 27 -> Ok(Version(1))
        c if c <= 48 -> Ok(Version(2))
        c if c <= 77 -> Ok(Version(3))
        c if c <= 111 -> Ok(Version(4))
        c if c <= 144 -> Ok(Version(5))
        c if c <= 178 -> Ok(Version(6))
        c if c <= 207 -> Ok(Version(7))
        c if c <= 259 -> Ok(Version(8))
        c if c <= 312 -> Ok(Version(9))
        c if c <= 364 -> Ok(Version(10))
        c if c <= 427 -> Ok(Version(11))
        c if c <= 489 -> Ok(Version(12))
        c if c <= 580 -> Ok(Version(13))
        c if c <= 621 -> Ok(Version(14))
        c if c <= 703 -> Ok(Version(15))
        c if c <= 775 -> Ok(Version(16))
        c if c <= 876 -> Ok(Version(17))
        c if c <= 948 -> Ok(Version(18))
        c if c <= 1063 -> Ok(Version(19))
        c if c <= 1159 -> Ok(Version(20))
        c if c <= 1224 -> Ok(Version(21))
        c if c <= 1358 -> Ok(Version(22))
        c if c <= 1468 -> Ok(Version(23))
        c if c <= 1588 -> Ok(Version(24))
        c if c <= 1718 -> Ok(Version(25))
        c if c <= 1804 -> Ok(Version(26))
        c if c <= 1933 -> Ok(Version(27))
        c if c <= 2085 -> Ok(Version(28))
        c if c <= 2181 -> Ok(Version(29))
        c if c <= 2358 -> Ok(Version(30))
        c if c <= 2473 -> Ok(Version(31))
        c if c <= 2670 -> Ok(Version(32))
        c if c <= 2805 -> Ok(Version(33))
        c if c <= 2949 -> Ok(Version(34))
        c if c <= 3081 -> Ok(Version(35))
        c if c <= 3244 -> Ok(Version(36))
        c if c <= 3417 -> Ok(Version(37))
        c if c <= 3599 -> Ok(Version(38))
        c if c <= 3791 -> Ok(Version(39))
        c if c <= 3993 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 3993,
          ))
      }
    H ->
      case count {
        c if c <= 17 -> Ok(Version(1))
        c if c <= 34 -> Ok(Version(2))
        c if c <= 58 -> Ok(Version(3))
        c if c <= 82 -> Ok(Version(4))
        c if c <= 106 -> Ok(Version(5))
        c if c <= 139 -> Ok(Version(6))
        c if c <= 154 -> Ok(Version(7))
        c if c <= 202 -> Ok(Version(8))
        c if c <= 235 -> Ok(Version(9))
        c if c <= 288 -> Ok(Version(10))
        c if c <= 331 -> Ok(Version(11))
        c if c <= 374 -> Ok(Version(12))
        c if c <= 427 -> Ok(Version(13))
        c if c <= 468 -> Ok(Version(14))
        c if c <= 530 -> Ok(Version(15))
        c if c <= 602 -> Ok(Version(16))
        c if c <= 674 -> Ok(Version(17))
        c if c <= 746 -> Ok(Version(18))
        c if c <= 813 -> Ok(Version(19))
        c if c <= 919 -> Ok(Version(20))
        c if c <= 969 -> Ok(Version(21))
        c if c <= 1056 -> Ok(Version(22))
        c if c <= 1108 -> Ok(Version(23))
        c if c <= 1228 -> Ok(Version(24))
        c if c <= 1286 -> Ok(Version(25))
        c if c <= 1425 -> Ok(Version(26))
        c if c <= 1501 -> Ok(Version(27))
        c if c <= 1581 -> Ok(Version(28))
        c if c <= 1677 -> Ok(Version(29))
        c if c <= 1782 -> Ok(Version(30))
        c if c <= 1897 -> Ok(Version(31))
        c if c <= 2022 -> Ok(Version(32))
        c if c <= 2157 -> Ok(Version(33))
        c if c <= 2301 -> Ok(Version(34))
        c if c <= 2361 -> Ok(Version(35))
        c if c <= 2524 -> Ok(Version(36))
        c if c <= 2625 -> Ok(Version(37))
        c if c <= 2735 -> Ok(Version(38))
        c if c <= 2927 -> Ok(Version(39))
        c if c <= 3057 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 3057,
          ))
      }
  }
}

fn find_version_alphanumeric(
  count: Int,
  level: ErrorCorrectionLevel,
) -> Result(Version, GenerateError) {
  case level {
    L ->
      case count {
        c if c <= 25 -> Ok(Version(1))
        c if c <= 47 -> Ok(Version(2))
        c if c <= 77 -> Ok(Version(3))
        c if c <= 114 -> Ok(Version(4))
        c if c <= 154 -> Ok(Version(5))
        c if c <= 195 -> Ok(Version(6))
        c if c <= 224 -> Ok(Version(7))
        c if c <= 279 -> Ok(Version(8))
        c if c <= 335 -> Ok(Version(9))
        c if c <= 395 -> Ok(Version(10))
        c if c <= 468 -> Ok(Version(11))
        c if c <= 535 -> Ok(Version(12))
        c if c <= 619 -> Ok(Version(13))
        c if c <= 667 -> Ok(Version(14))
        c if c <= 758 -> Ok(Version(15))
        c if c <= 854 -> Ok(Version(16))
        c if c <= 938 -> Ok(Version(17))
        c if c <= 1046 -> Ok(Version(18))
        c if c <= 1153 -> Ok(Version(19))
        c if c <= 1249 -> Ok(Version(20))
        c if c <= 1352 -> Ok(Version(21))
        c if c <= 1460 -> Ok(Version(22))
        c if c <= 1588 -> Ok(Version(23))
        c if c <= 1704 -> Ok(Version(24))
        c if c <= 1853 -> Ok(Version(25))
        c if c <= 1990 -> Ok(Version(26))
        c if c <= 2132 -> Ok(Version(27))
        c if c <= 2223 -> Ok(Version(28))
        c if c <= 2369 -> Ok(Version(29))
        c if c <= 2520 -> Ok(Version(30))
        c if c <= 2677 -> Ok(Version(31))
        c if c <= 2840 -> Ok(Version(32))
        c if c <= 3009 -> Ok(Version(33))
        c if c <= 3183 -> Ok(Version(34))
        c if c <= 3351 -> Ok(Version(35))
        c if c <= 3537 -> Ok(Version(36))
        c if c <= 3729 -> Ok(Version(37))
        c if c <= 3927 -> Ok(Version(38))
        c if c <= 4087 -> Ok(Version(39))
        c if c <= 4296 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 4296,
          ))
      }
    M ->
      case count {
        c if c <= 20 -> Ok(Version(1))
        c if c <= 38 -> Ok(Version(2))
        c if c <= 61 -> Ok(Version(3))
        c if c <= 90 -> Ok(Version(4))
        c if c <= 122 -> Ok(Version(5))
        c if c <= 154 -> Ok(Version(6))
        c if c <= 178 -> Ok(Version(7))
        c if c <= 221 -> Ok(Version(8))
        c if c <= 262 -> Ok(Version(9))
        c if c <= 311 -> Ok(Version(10))
        c if c <= 366 -> Ok(Version(11))
        c if c <= 419 -> Ok(Version(12))
        c if c <= 483 -> Ok(Version(13))
        c if c <= 528 -> Ok(Version(14))
        c if c <= 600 -> Ok(Version(15))
        c if c <= 656 -> Ok(Version(16))
        c if c <= 734 -> Ok(Version(17))
        c if c <= 816 -> Ok(Version(18))
        c if c <= 909 -> Ok(Version(19))
        c if c <= 970 -> Ok(Version(20))
        c if c <= 1035 -> Ok(Version(21))
        c if c <= 1134 -> Ok(Version(22))
        c if c <= 1248 -> Ok(Version(23))
        c if c <= 1326 -> Ok(Version(24))
        c if c <= 1451 -> Ok(Version(25))
        c if c <= 1542 -> Ok(Version(26))
        c if c <= 1637 -> Ok(Version(27))
        c if c <= 1732 -> Ok(Version(28))
        c if c <= 1839 -> Ok(Version(29))
        c if c <= 1994 -> Ok(Version(30))
        c if c <= 2113 -> Ok(Version(31))
        c if c <= 2238 -> Ok(Version(32))
        c if c <= 2369 -> Ok(Version(33))
        c if c <= 2506 -> Ok(Version(34))
        c if c <= 2632 -> Ok(Version(35))
        c if c <= 2780 -> Ok(Version(36))
        c if c <= 2894 -> Ok(Version(37))
        c if c <= 3054 -> Ok(Version(38))
        c if c <= 3220 -> Ok(Version(39))
        c if c <= 3391 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 3391,
          ))
      }
    Q ->
      case count {
        c if c <= 16 -> Ok(Version(1))
        c if c <= 29 -> Ok(Version(2))
        c if c <= 47 -> Ok(Version(3))
        c if c <= 67 -> Ok(Version(4))
        c if c <= 87 -> Ok(Version(5))
        c if c <= 108 -> Ok(Version(6))
        c if c <= 125 -> Ok(Version(7))
        c if c <= 157 -> Ok(Version(8))
        c if c <= 189 -> Ok(Version(9))
        c if c <= 221 -> Ok(Version(10))
        c if c <= 259 -> Ok(Version(11))
        c if c <= 296 -> Ok(Version(12))
        c if c <= 352 -> Ok(Version(13))
        c if c <= 376 -> Ok(Version(14))
        c if c <= 426 -> Ok(Version(15))
        c if c <= 470 -> Ok(Version(16))
        c if c <= 531 -> Ok(Version(17))
        c if c <= 574 -> Ok(Version(18))
        c if c <= 644 -> Ok(Version(19))
        c if c <= 702 -> Ok(Version(20))
        c if c <= 742 -> Ok(Version(21))
        c if c <= 823 -> Ok(Version(22))
        c if c <= 890 -> Ok(Version(23))
        c if c <= 963 -> Ok(Version(24))
        c if c <= 1041 -> Ok(Version(25))
        c if c <= 1094 -> Ok(Version(26))
        c if c <= 1172 -> Ok(Version(27))
        c if c <= 1263 -> Ok(Version(28))
        c if c <= 1322 -> Ok(Version(29))
        c if c <= 1429 -> Ok(Version(30))
        c if c <= 1499 -> Ok(Version(31))
        c if c <= 1618 -> Ok(Version(32))
        c if c <= 1700 -> Ok(Version(33))
        c if c <= 1787 -> Ok(Version(34))
        c if c <= 1867 -> Ok(Version(35))
        c if c <= 1966 -> Ok(Version(36))
        c if c <= 2071 -> Ok(Version(37))
        c if c <= 2181 -> Ok(Version(38))
        c if c <= 2298 -> Ok(Version(39))
        c if c <= 2420 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 2420,
          ))
      }
    H ->
      case count {
        c if c <= 10 -> Ok(Version(1))
        c if c <= 20 -> Ok(Version(2))
        c if c <= 35 -> Ok(Version(3))
        c if c <= 50 -> Ok(Version(4))
        c if c <= 64 -> Ok(Version(5))
        c if c <= 84 -> Ok(Version(6))
        c if c <= 93 -> Ok(Version(7))
        c if c <= 122 -> Ok(Version(8))
        c if c <= 143 -> Ok(Version(9))
        c if c <= 174 -> Ok(Version(10))
        c if c <= 200 -> Ok(Version(11))
        c if c <= 227 -> Ok(Version(12))
        c if c <= 259 -> Ok(Version(13))
        c if c <= 283 -> Ok(Version(14))
        c if c <= 321 -> Ok(Version(15))
        c if c <= 365 -> Ok(Version(16))
        c if c <= 408 -> Ok(Version(17))
        c if c <= 452 -> Ok(Version(18))
        c if c <= 493 -> Ok(Version(19))
        c if c <= 557 -> Ok(Version(20))
        c if c <= 587 -> Ok(Version(21))
        c if c <= 640 -> Ok(Version(22))
        c if c <= 672 -> Ok(Version(23))
        c if c <= 744 -> Ok(Version(24))
        c if c <= 779 -> Ok(Version(25))
        c if c <= 864 -> Ok(Version(26))
        c if c <= 910 -> Ok(Version(27))
        c if c <= 958 -> Ok(Version(28))
        c if c <= 1016 -> Ok(Version(29))
        c if c <= 1080 -> Ok(Version(30))
        c if c <= 1150 -> Ok(Version(31))
        c if c <= 1226 -> Ok(Version(32))
        c if c <= 1307 -> Ok(Version(33))
        c if c <= 1394 -> Ok(Version(34))
        c if c <= 1431 -> Ok(Version(35))
        c if c <= 1530 -> Ok(Version(36))
        c if c <= 1591 -> Ok(Version(37))
        c if c <= 1658 -> Ok(Version(38))
        c if c <= 1774 -> Ok(Version(39))
        c if c <= 1852 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 1852,
          ))
      }
  }
}

fn find_version_utf8(
  count: Int,
  level: ErrorCorrectionLevel,
) -> Result(Version, GenerateError) {
  case level {
    L ->
      case count {
        c if c <= 17 -> Ok(Version(1))
        c if c <= 32 -> Ok(Version(2))
        c if c <= 53 -> Ok(Version(3))
        c if c <= 78 -> Ok(Version(4))
        c if c <= 106 -> Ok(Version(5))
        c if c <= 134 -> Ok(Version(6))
        c if c <= 154 -> Ok(Version(7))
        c if c <= 192 -> Ok(Version(8))
        c if c <= 230 -> Ok(Version(9))
        c if c <= 271 -> Ok(Version(10))
        c if c <= 321 -> Ok(Version(11))
        c if c <= 367 -> Ok(Version(12))
        c if c <= 425 -> Ok(Version(13))
        c if c <= 458 -> Ok(Version(14))
        c if c <= 520 -> Ok(Version(15))
        c if c <= 586 -> Ok(Version(16))
        c if c <= 644 -> Ok(Version(17))
        c if c <= 718 -> Ok(Version(18))
        c if c <= 792 -> Ok(Version(19))
        c if c <= 858 -> Ok(Version(20))
        c if c <= 929 -> Ok(Version(21))
        c if c <= 1003 -> Ok(Version(22))
        c if c <= 1091 -> Ok(Version(23))
        c if c <= 1171 -> Ok(Version(24))
        c if c <= 1273 -> Ok(Version(25))
        c if c <= 1367 -> Ok(Version(26))
        c if c <= 1465 -> Ok(Version(27))
        c if c <= 1528 -> Ok(Version(28))
        c if c <= 1628 -> Ok(Version(29))
        c if c <= 1732 -> Ok(Version(30))
        c if c <= 1840 -> Ok(Version(31))
        c if c <= 1952 -> Ok(Version(32))
        c if c <= 2068 -> Ok(Version(33))
        c if c <= 2188 -> Ok(Version(34))
        c if c <= 2303 -> Ok(Version(35))
        c if c <= 2431 -> Ok(Version(36))
        c if c <= 2563 -> Ok(Version(37))
        c if c <= 2699 -> Ok(Version(38))
        c if c <= 2809 -> Ok(Version(39))
        c if c <= 2953 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 2953,
          ))
      }
    M ->
      case count {
        c if c <= 14 -> Ok(Version(1))
        c if c <= 26 -> Ok(Version(2))
        c if c <= 42 -> Ok(Version(3))
        c if c <= 62 -> Ok(Version(4))
        c if c <= 84 -> Ok(Version(5))
        c if c <= 106 -> Ok(Version(6))
        c if c <= 122 -> Ok(Version(7))
        c if c <= 152 -> Ok(Version(8))
        c if c <= 180 -> Ok(Version(9))
        c if c <= 213 -> Ok(Version(10))
        c if c <= 251 -> Ok(Version(11))
        c if c <= 287 -> Ok(Version(12))
        c if c <= 331 -> Ok(Version(13))
        c if c <= 362 -> Ok(Version(14))
        c if c <= 412 -> Ok(Version(15))
        c if c <= 450 -> Ok(Version(16))
        c if c <= 504 -> Ok(Version(17))
        c if c <= 560 -> Ok(Version(18))
        c if c <= 624 -> Ok(Version(19))
        c if c <= 666 -> Ok(Version(20))
        c if c <= 711 -> Ok(Version(21))
        c if c <= 779 -> Ok(Version(22))
        c if c <= 857 -> Ok(Version(23))
        c if c <= 911 -> Ok(Version(24))
        c if c <= 997 -> Ok(Version(25))
        c if c <= 1059 -> Ok(Version(26))
        c if c <= 1125 -> Ok(Version(27))
        c if c <= 1190 -> Ok(Version(28))
        c if c <= 1264 -> Ok(Version(29))
        c if c <= 1370 -> Ok(Version(30))
        c if c <= 1452 -> Ok(Version(31))
        c if c <= 1538 -> Ok(Version(32))
        c if c <= 1628 -> Ok(Version(33))
        c if c <= 1722 -> Ok(Version(34))
        c if c <= 1809 -> Ok(Version(35))
        c if c <= 1911 -> Ok(Version(36))
        c if c <= 1989 -> Ok(Version(37))
        c if c <= 2099 -> Ok(Version(38))
        c if c <= 2213 -> Ok(Version(39))
        c if c <= 2331 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 2331,
          ))
      }
    Q ->
      case count {
        c if c <= 11 -> Ok(Version(1))
        c if c <= 20 -> Ok(Version(2))
        c if c <= 32 -> Ok(Version(3))
        c if c <= 46 -> Ok(Version(4))
        c if c <= 60 -> Ok(Version(5))
        c if c <= 74 -> Ok(Version(6))
        c if c <= 86 -> Ok(Version(7))
        c if c <= 108 -> Ok(Version(8))
        c if c <= 130 -> Ok(Version(9))
        c if c <= 151 -> Ok(Version(10))
        c if c <= 177 -> Ok(Version(11))
        c if c <= 203 -> Ok(Version(12))
        c if c <= 241 -> Ok(Version(13))
        c if c <= 258 -> Ok(Version(14))
        c if c <= 292 -> Ok(Version(15))
        c if c <= 322 -> Ok(Version(16))
        c if c <= 364 -> Ok(Version(17))
        c if c <= 394 -> Ok(Version(18))
        c if c <= 442 -> Ok(Version(19))
        c if c <= 482 -> Ok(Version(20))
        c if c <= 509 -> Ok(Version(21))
        c if c <= 565 -> Ok(Version(22))
        c if c <= 611 -> Ok(Version(23))
        c if c <= 661 -> Ok(Version(24))
        c if c <= 715 -> Ok(Version(25))
        c if c <= 751 -> Ok(Version(26))
        c if c <= 805 -> Ok(Version(27))
        c if c <= 868 -> Ok(Version(28))
        c if c <= 908 -> Ok(Version(29))
        c if c <= 982 -> Ok(Version(30))
        c if c <= 1030 -> Ok(Version(31))
        c if c <= 1112 -> Ok(Version(32))
        c if c <= 1168 -> Ok(Version(33))
        c if c <= 1228 -> Ok(Version(34))
        c if c <= 1283 -> Ok(Version(35))
        c if c <= 1351 -> Ok(Version(36))
        c if c <= 1423 -> Ok(Version(37))
        c if c <= 1499 -> Ok(Version(38))
        c if c <= 1579 -> Ok(Version(39))
        c if c <= 1663 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 1663,
          ))
      }
    H ->
      case count {
        c if c <= 7 -> Ok(Version(1))
        c if c <= 14 -> Ok(Version(2))
        c if c <= 24 -> Ok(Version(3))
        c if c <= 34 -> Ok(Version(4))
        c if c <= 44 -> Ok(Version(5))
        c if c <= 58 -> Ok(Version(6))
        c if c <= 64 -> Ok(Version(7))
        c if c <= 84 -> Ok(Version(8))
        c if c <= 98 -> Ok(Version(9))
        c if c <= 119 -> Ok(Version(10))
        c if c <= 137 -> Ok(Version(11))
        c if c <= 155 -> Ok(Version(12))
        c if c <= 177 -> Ok(Version(13))
        c if c <= 194 -> Ok(Version(14))
        c if c <= 220 -> Ok(Version(15))
        c if c <= 250 -> Ok(Version(16))
        c if c <= 280 -> Ok(Version(17))
        c if c <= 310 -> Ok(Version(18))
        c if c <= 338 -> Ok(Version(19))
        c if c <= 382 -> Ok(Version(20))
        c if c <= 403 -> Ok(Version(21))
        c if c <= 439 -> Ok(Version(22))
        c if c <= 461 -> Ok(Version(23))
        c if c <= 511 -> Ok(Version(24))
        c if c <= 535 -> Ok(Version(25))
        c if c <= 593 -> Ok(Version(26))
        c if c <= 625 -> Ok(Version(27))
        c if c <= 658 -> Ok(Version(28))
        c if c <= 698 -> Ok(Version(29))
        c if c <= 742 -> Ok(Version(30))
        c if c <= 790 -> Ok(Version(31))
        c if c <= 842 -> Ok(Version(32))
        c if c <= 898 -> Ok(Version(33))
        c if c <= 958 -> Ok(Version(34))
        c if c <= 983 -> Ok(Version(35))
        c if c <= 1051 -> Ok(Version(36))
        c if c <= 1093 -> Ok(Version(37))
        c if c <= 1139 -> Ok(Version(38))
        c if c <= 1219 -> Ok(Version(39))
        c if c <= 1273 -> Ok(Version(40))
        _ ->
          Error(ProvidedValueExceedsCapacity(
            value_length: count,
            capacity: 1273,
          ))
      }
  }
}

fn version_size(version: Version) -> Int {
  let Version(v) = version
  v * 4 + 17
}

fn ec_info(version: Version, level: ErrorCorrectionLevel) -> ECInfo {
  let Version(v) = version
  case v, level {
    1, L -> ECInfo(19, 7, 1, 19, 0, 0)
    1, M -> ECInfo(16, 10, 1, 16, 0, 0)
    1, Q -> ECInfo(13, 13, 1, 13, 0, 0)
    1, H -> ECInfo(9, 17, 1, 9, 0, 0)
    2, L -> ECInfo(34, 10, 1, 34, 0, 0)
    2, M -> ECInfo(28, 16, 1, 28, 0, 0)
    2, Q -> ECInfo(22, 22, 1, 22, 0, 0)
    2, H -> ECInfo(16, 28, 1, 16, 0, 0)
    3, L -> ECInfo(55, 15, 1, 55, 0, 0)
    3, M -> ECInfo(44, 26, 1, 44, 0, 0)
    3, Q -> ECInfo(34, 18, 2, 17, 0, 0)
    3, H -> ECInfo(26, 22, 2, 13, 0, 0)
    4, L -> ECInfo(80, 20, 1, 80, 0, 0)
    4, M -> ECInfo(64, 18, 2, 32, 0, 0)
    4, Q -> ECInfo(48, 26, 2, 24, 0, 0)
    4, H -> ECInfo(36, 16, 4, 9, 0, 0)
    5, L -> ECInfo(108, 26, 1, 108, 0, 0)
    5, M -> ECInfo(86, 24, 2, 43, 0, 0)
    5, Q -> ECInfo(62, 18, 2, 15, 2, 16)
    5, H -> ECInfo(46, 22, 2, 11, 2, 12)
    6, L -> ECInfo(136, 18, 2, 68, 0, 0)
    6, M -> ECInfo(108, 16, 4, 27, 0, 0)
    6, Q -> ECInfo(76, 24, 4, 19, 0, 0)
    6, H -> ECInfo(60, 28, 4, 15, 0, 0)
    7, L -> ECInfo(156, 20, 2, 78, 0, 0)
    7, M -> ECInfo(124, 18, 4, 31, 0, 0)
    7, Q -> ECInfo(88, 18, 2, 14, 4, 15)
    7, H -> ECInfo(66, 26, 4, 13, 1, 14)
    8, L -> ECInfo(194, 24, 2, 97, 0, 0)
    8, M -> ECInfo(154, 22, 2, 38, 2, 39)
    8, Q -> ECInfo(110, 22, 4, 18, 2, 19)
    8, H -> ECInfo(86, 26, 4, 14, 2, 15)
    9, L -> ECInfo(232, 30, 2, 116, 0, 0)
    9, M -> ECInfo(182, 22, 3, 36, 2, 37)
    9, Q -> ECInfo(132, 20, 4, 16, 4, 17)
    9, H -> ECInfo(100, 24, 4, 12, 4, 13)
    10, L -> ECInfo(274, 18, 2, 68, 2, 69)
    10, M -> ECInfo(216, 26, 4, 43, 1, 44)
    10, Q -> ECInfo(154, 24, 6, 19, 2, 20)
    10, H -> ECInfo(122, 28, 6, 15, 2, 16)
    11, L -> ECInfo(324, 20, 4, 81, 0, 0)
    11, M -> ECInfo(254, 30, 1, 50, 4, 51)
    11, Q -> ECInfo(180, 28, 4, 22, 4, 23)
    11, H -> ECInfo(140, 24, 3, 12, 8, 13)
    12, L -> ECInfo(370, 24, 2, 92, 2, 93)
    12, M -> ECInfo(290, 22, 6, 36, 2, 37)
    12, Q -> ECInfo(206, 26, 4, 20, 6, 21)
    12, H -> ECInfo(158, 28, 7, 14, 4, 15)
    13, L -> ECInfo(428, 26, 4, 107, 0, 0)
    13, M -> ECInfo(334, 22, 8, 37, 1, 38)
    13, Q -> ECInfo(244, 24, 8, 20, 4, 21)
    13, H -> ECInfo(180, 22, 12, 11, 4, 12)
    14, L -> ECInfo(461, 30, 3, 115, 1, 116)
    14, M -> ECInfo(365, 24, 4, 40, 5, 41)
    14, Q -> ECInfo(261, 20, 11, 16, 5, 17)
    14, H -> ECInfo(197, 24, 11, 12, 5, 13)
    15, L -> ECInfo(523, 22, 5, 87, 1, 88)
    15, M -> ECInfo(415, 24, 5, 41, 5, 42)
    15, Q -> ECInfo(295, 30, 5, 24, 7, 25)
    15, H -> ECInfo(223, 24, 11, 12, 7, 13)
    16, L -> ECInfo(589, 24, 5, 98, 1, 99)
    16, M -> ECInfo(453, 28, 7, 45, 3, 46)
    16, Q -> ECInfo(325, 24, 15, 19, 2, 20)
    16, H -> ECInfo(253, 30, 3, 15, 13, 16)
    17, L -> ECInfo(647, 28, 1, 107, 5, 108)
    17, M -> ECInfo(507, 28, 10, 46, 1, 47)
    17, Q -> ECInfo(367, 28, 1, 22, 15, 23)
    17, H -> ECInfo(283, 28, 2, 14, 17, 15)
    18, L -> ECInfo(721, 30, 5, 120, 1, 121)
    18, M -> ECInfo(563, 26, 9, 43, 4, 44)
    18, Q -> ECInfo(397, 28, 17, 22, 1, 23)
    18, H -> ECInfo(313, 28, 2, 14, 19, 15)
    19, L -> ECInfo(795, 28, 3, 113, 4, 114)
    19, M -> ECInfo(627, 26, 3, 44, 11, 45)
    19, Q -> ECInfo(445, 26, 17, 21, 4, 22)
    19, H -> ECInfo(341, 26, 9, 13, 16, 14)
    20, L -> ECInfo(861, 28, 3, 107, 5, 108)
    20, M -> ECInfo(669, 26, 3, 41, 13, 42)
    20, Q -> ECInfo(485, 30, 15, 24, 5, 25)
    20, H -> ECInfo(385, 28, 15, 15, 10, 16)
    21, L -> ECInfo(932, 28, 4, 116, 4, 117)
    21, M -> ECInfo(714, 26, 17, 42, 0, 0)
    21, Q -> ECInfo(512, 28, 17, 22, 6, 23)
    21, H -> ECInfo(406, 30, 19, 16, 6, 17)
    22, L -> ECInfo(1006, 28, 2, 111, 7, 112)
    22, M -> ECInfo(782, 28, 17, 46, 0, 0)
    22, Q -> ECInfo(568, 30, 7, 24, 16, 25)
    22, H -> ECInfo(442, 24, 34, 13, 0, 0)
    23, L -> ECInfo(1094, 30, 4, 121, 5, 122)
    23, M -> ECInfo(860, 28, 4, 47, 14, 48)
    23, Q -> ECInfo(614, 30, 11, 24, 14, 25)
    23, H -> ECInfo(464, 30, 16, 15, 14, 16)
    24, L -> ECInfo(1174, 30, 6, 117, 4, 118)
    24, M -> ECInfo(914, 28, 6, 45, 14, 46)
    24, Q -> ECInfo(664, 30, 11, 24, 16, 25)
    24, H -> ECInfo(514, 30, 30, 16, 2, 17)
    25, L -> ECInfo(1276, 26, 8, 106, 4, 107)
    25, M -> ECInfo(1000, 28, 8, 47, 13, 48)
    25, Q -> ECInfo(718, 30, 7, 24, 22, 25)
    25, H -> ECInfo(538, 30, 22, 15, 13, 16)
    26, L -> ECInfo(1370, 28, 10, 114, 2, 115)
    26, M -> ECInfo(1062, 28, 19, 46, 4, 47)
    26, Q -> ECInfo(754, 28, 28, 22, 6, 23)
    26, H -> ECInfo(596, 30, 33, 16, 4, 17)
    27, L -> ECInfo(1468, 30, 8, 122, 4, 123)
    27, M -> ECInfo(1128, 28, 22, 45, 3, 46)
    27, Q -> ECInfo(808, 30, 8, 23, 26, 24)
    27, H -> ECInfo(628, 30, 12, 15, 28, 16)
    28, L -> ECInfo(1531, 30, 3, 117, 10, 118)
    28, M -> ECInfo(1193, 28, 3, 45, 23, 46)
    28, Q -> ECInfo(871, 30, 4, 24, 31, 25)
    28, H -> ECInfo(661, 30, 11, 15, 31, 16)
    29, L -> ECInfo(1631, 30, 7, 116, 7, 117)
    29, M -> ECInfo(1267, 28, 21, 45, 7, 46)
    29, Q -> ECInfo(911, 30, 1, 23, 37, 24)
    29, H -> ECInfo(701, 30, 19, 15, 26, 16)
    30, L -> ECInfo(1735, 30, 5, 115, 10, 116)
    30, M -> ECInfo(1373, 28, 19, 47, 10, 48)
    30, Q -> ECInfo(985, 30, 15, 24, 25, 25)
    30, H -> ECInfo(745, 30, 23, 15, 25, 16)
    31, L -> ECInfo(1843, 30, 13, 115, 3, 116)
    31, M -> ECInfo(1455, 28, 2, 46, 29, 47)
    31, Q -> ECInfo(1033, 30, 42, 24, 1, 25)
    31, H -> ECInfo(793, 30, 23, 15, 28, 16)
    32, L -> ECInfo(1955, 30, 17, 115, 0, 0)
    32, M -> ECInfo(1541, 28, 10, 46, 23, 47)
    32, Q -> ECInfo(1115, 30, 10, 24, 35, 25)
    32, H -> ECInfo(845, 30, 19, 15, 35, 16)
    33, L -> ECInfo(2071, 30, 17, 115, 1, 116)
    33, M -> ECInfo(1631, 28, 14, 46, 21, 47)
    33, Q -> ECInfo(1171, 30, 29, 24, 19, 25)
    33, H -> ECInfo(901, 30, 11, 15, 46, 16)
    34, L -> ECInfo(2191, 30, 13, 115, 6, 116)
    34, M -> ECInfo(1725, 28, 14, 46, 23, 47)
    34, Q -> ECInfo(1231, 30, 44, 24, 7, 25)
    34, H -> ECInfo(961, 30, 59, 16, 1, 17)
    35, L -> ECInfo(2306, 30, 12, 121, 7, 122)
    35, M -> ECInfo(1812, 28, 12, 47, 26, 48)
    35, Q -> ECInfo(1286, 30, 39, 24, 14, 25)
    35, H -> ECInfo(986, 30, 22, 15, 41, 16)
    36, L -> ECInfo(2434, 30, 6, 121, 14, 122)
    36, M -> ECInfo(1914, 28, 6, 47, 34, 48)
    36, Q -> ECInfo(1354, 30, 46, 24, 10, 25)
    36, H -> ECInfo(1054, 30, 2, 15, 64, 16)
    37, L -> ECInfo(2566, 30, 17, 122, 4, 123)
    37, M -> ECInfo(1992, 28, 29, 46, 14, 47)
    37, Q -> ECInfo(1426, 30, 49, 24, 10, 25)
    37, H -> ECInfo(1096, 30, 24, 15, 46, 16)
    38, L -> ECInfo(2702, 30, 4, 122, 18, 123)
    38, M -> ECInfo(2102, 28, 13, 46, 32, 47)
    38, Q -> ECInfo(1502, 30, 48, 24, 14, 25)
    38, H -> ECInfo(1142, 30, 42, 15, 32, 16)
    39, L -> ECInfo(2812, 30, 20, 117, 4, 118)
    39, M -> ECInfo(2216, 28, 40, 47, 7, 48)
    39, Q -> ECInfo(1582, 30, 43, 24, 22, 25)
    39, H -> ECInfo(1222, 30, 10, 15, 67, 16)
    40, L -> ECInfo(2956, 30, 19, 118, 6, 119)
    40, M -> ECInfo(2334, 28, 18, 47, 31, 48)
    40, Q -> ECInfo(1666, 30, 34, 24, 34, 25)
    40, H -> ECInfo(1276, 30, 20, 15, 61, 16)
    _, _ -> ECInfo(0, 0, 0, 0, 0, 0)
  }
}

fn data_bit_count(
  value: String,
  count: Int,
  mode: EncodingMode,
  version: Version,
) -> Int {
  let mode_indicator_size = 4
  let character_indicator_size = character_indicator_size(mode, version)
  let encode_size = case mode {
    Numeric -> {
      let full = count / 3
      let remainder = count % 3
      full
      * 10
      + case remainder {
        2 -> 7
        1 -> 4
        _ -> 0
      }
    }
    Alphanumeric -> {
      let full = count / 2
      let remainder = count % 2
      full
      * 11
      + case remainder {
        1 -> 6
        _ -> 0
      }
    }
    UTF8 -> {
      bit_array.byte_size(bit_array.from_string(value)) * 8
    }
  }
  encode_size + mode_indicator_size + character_indicator_size
}

fn terminator_bit_count(
  value: String,
  count: Int,
  mode: EncodingMode,
  version: Version,
  level: ErrorCorrectionLevel,
) -> Int {
  let bit_count = data_bit_count(value, count, mode, version)
  let required_bits = required_bits(version, level)
  case required_bits - bit_count {
    x if x >= 4 -> 4
    x if x > 0 -> x
    _ -> 0
  }
}

fn terminator_padding_bit_count(size: Int) -> Int {
  case size % 8 {
    0 -> 0
    x -> 8 - x
  }
}

fn generate_padding_bits(
  iterations,
  use_ec: Bool,
  current: BitArray,
) -> BitArray {
  case iterations {
    0 -> current
    _ -> {
      let #(byte, next_use_ec) = case use_ec {
        True -> #(236, False)
        False -> #(17, True)
      }
      generate_padding_bits(iterations - 1, next_use_ec, <<
        current:bits,
        byte:size(8),
      >>)
    }
  }
}

fn encoding_padding_bytes(remainder: Int) -> Result(BitArray, GenerateError) {
  case remainder % 8 {
    0 -> {
      let iterations = remainder / 8
      Ok(generate_padding_bits(iterations, True, <<>>))
    }
    _ ->
      Error(InvalidRemainingBits(
        "After adding the terminator bits, the total bit count should be a multiple of 8. Please report this as a bug with the input value: "
        <> int.to_string(remainder),
      ))
  }
}

fn bits_to_bytes(bits: BitArray) -> List(Int) {
  bits_to_bytes_loop(bits, [])
  |> list.reverse
}

fn bits_to_bytes_loop(bits: BitArray, acc: List(Int)) -> List(Int) {
  case bits {
    <<byte, rest:bytes>> -> bits_to_bytes_loop(rest, [byte, ..acc])
    _ -> acc
  }
}

fn bytes_to_bits(bytes: List(Int)) -> BitArray {
  list.fold(bytes, <<>>, fn(acc, byte) { <<acc:bits, byte:size(8)>> })
}

fn gf_multiply(a: Int, b: Int) -> Int {
  case a, b {
    0, _ -> 0
    _, 0 -> 0
    _, _ -> gf_exp({ gf_log(a) + gf_log(b) } % 255)
  }
}

fn build_generator_poly(ec_count: Int, current: List(Int)) -> List(Int) {
  case ec_count {
    0 -> current
    _ -> {
      let next_gen = gf_poly_multiply(current, [1, gf_exp(ec_count - 1)])
      build_generator_poly(ec_count - 1, next_gen)
    }
  }
}

fn gf_poly_multiply(p1: List(Int), p2: List(Int)) -> List(Int) {
  let result_len = list.length(p1) + list.length(p2) - 1
  let zeros = list.repeat(0, result_len)
  p1
  |> list.index_fold(zeros, fn(result, coeff1, i) {
    p2
    |> list.index_fold(result, fn(acc, coeff2, j) {
      let product = gf_multiply(coeff1, coeff2)
      list_xor_at(acc, i + j, product)
    })
  })
}

fn list_xor_at(lst: List(Int), pos: Int, value: Int) -> List(Int) {
  list.index_map(lst, fn(elem, i) {
    case i == pos {
      True -> int.bitwise_exclusive_or(elem, value)
      False -> elem
    }
  })
}

fn compute_ec_codewords(data: List(Int), generator: List(Int)) -> List(Int) {
  let ec_count = list.length(generator) - 1
  let message = list.append(data, list.repeat(0, ec_count))
  poly_divide_loop(message, generator, list.length(data))
}

fn poly_divide_loop(
  message: List(Int),
  generator: List(Int),
  steps: Int,
) -> List(Int) {
  case steps {
    0 -> message
    _ ->
      case message {
        [0, ..rest] -> poly_divide_loop(rest, generator, steps - 1)
        [lead, ..rest] -> {
          let lead_log = gf_log(lead)
          let new_message =
            xor_with_generator(rest, list.drop(generator, 1), lead_log)
          poly_divide_loop(new_message, generator, steps - 1)
        }
        [] -> []
      }
  }
}

fn xor_with_generator(
  message: List(Int),
  gen_tail: List(Int),
  lead_log: Int,
) -> List(Int) {
  case message, gen_tail {
    [m, ..m_rest], [g, ..g_rest] -> {
      let xor_val = gf_exp({ gf_log(g) + lead_log } % 255)
      [
        int.bitwise_exclusive_or(m, xor_val),
        ..xor_with_generator(m_rest, g_rest, lead_log)
      ]
    }
    _, [] -> message
    [], _ -> []
  }
}

fn split_into_blocks(
  data_bytes: List(Int),
  ec_info: ECInfo,
) -> #(List(List(Int)), List(List(Int))) {
  let #(group1_data, remaining) =
    split_n_blocks(data_bytes, ec_info.group1_blocks, ec_info.group1_block_size)
  let #(group2_data, _) =
    split_n_blocks(remaining, ec_info.group2_blocks, ec_info.group2_block_size)

  let all_data_blocks = list.append(group1_data, group2_data)
  let generator = build_generator_poly(ec_info.ec_codewords_per_block, [1])
  let ec_blocks =
    list.map(all_data_blocks, fn(block) {
      compute_ec_codewords(block, generator)
    })

  #(all_data_blocks, ec_blocks)
}

fn split_n_blocks(
  data: List(Int),
  num_blocks: Int,
  block_size: Int,
) -> #(List(List(Int)), List(Int)) {
  case num_blocks {
    0 -> #([], data)
    _ -> {
      let #(block, rest) = list.split(data, block_size)
      let #(more_blocks, remaining) =
        split_n_blocks(rest, num_blocks - 1, block_size)
      #([block, ..more_blocks], remaining)
    }
  }
}

fn interleave_blocks(
  data_blocks: List(List(Int)),
  ec_blocks: List(List(Int)),
  version: Version,
) -> BitArray {
  let interleaved_data = list.interleave(data_blocks)
  let interleaved_ec = list.interleave(ec_blocks)
  let all_codewords = list.append(interleaved_data, interleaved_ec)
  let bits = bytes_to_bits(all_codewords)
  let remainder = remainder_bit_count(version)
  <<bits:bits, 0:size(remainder)>>
}

fn remainder_bit_count(version: Version) -> Int {
  let Version(v) = version
  case v {
    1 -> 0
    v if v <= 6 -> 7
    v if v <= 13 -> 0
    v if v <= 20 -> 3
    v if v <= 27 -> 4
    v if v <= 34 -> 3
    _ -> 0
  }
}

fn gf_exp(i: Int) -> Int {
  case i {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    5 -> 32
    6 -> 64
    7 -> 128
    8 -> 29
    9 -> 58
    10 -> 116
    11 -> 232
    12 -> 205
    13 -> 135
    14 -> 19
    15 -> 38
    16 -> 76
    17 -> 152
    18 -> 45
    19 -> 90
    20 -> 180
    21 -> 117
    22 -> 234
    23 -> 201
    24 -> 143
    25 -> 3
    26 -> 6
    27 -> 12
    28 -> 24
    29 -> 48
    30 -> 96
    31 -> 192
    32 -> 157
    33 -> 39
    34 -> 78
    35 -> 156
    36 -> 37
    37 -> 74
    38 -> 148
    39 -> 53
    40 -> 106
    41 -> 212
    42 -> 181
    43 -> 119
    44 -> 238
    45 -> 193
    46 -> 159
    47 -> 35
    48 -> 70
    49 -> 140
    50 -> 5
    51 -> 10
    52 -> 20
    53 -> 40
    54 -> 80
    55 -> 160
    56 -> 93
    57 -> 186
    58 -> 105
    59 -> 210
    60 -> 185
    61 -> 111
    62 -> 222
    63 -> 161
    64 -> 95
    65 -> 190
    66 -> 97
    67 -> 194
    68 -> 153
    69 -> 47
    70 -> 94
    71 -> 188
    72 -> 101
    73 -> 202
    74 -> 137
    75 -> 15
    76 -> 30
    77 -> 60
    78 -> 120
    79 -> 240
    80 -> 253
    81 -> 231
    82 -> 211
    83 -> 187
    84 -> 107
    85 -> 214
    86 -> 177
    87 -> 127
    88 -> 254
    89 -> 225
    90 -> 223
    91 -> 163
    92 -> 91
    93 -> 182
    94 -> 113
    95 -> 226
    96 -> 217
    97 -> 175
    98 -> 67
    99 -> 134
    100 -> 17
    101 -> 34
    102 -> 68
    103 -> 136
    104 -> 13
    105 -> 26
    106 -> 52
    107 -> 104
    108 -> 208
    109 -> 189
    110 -> 103
    111 -> 206
    112 -> 129
    113 -> 31
    114 -> 62
    115 -> 124
    116 -> 248
    117 -> 237
    118 -> 199
    119 -> 147
    120 -> 59
    121 -> 118
    122 -> 236
    123 -> 197
    124 -> 151
    125 -> 51
    126 -> 102
    127 -> 204
    128 -> 133
    129 -> 23
    130 -> 46
    131 -> 92
    132 -> 184
    133 -> 109
    134 -> 218
    135 -> 169
    136 -> 79
    137 -> 158
    138 -> 33
    139 -> 66
    140 -> 132
    141 -> 21
    142 -> 42
    143 -> 84
    144 -> 168
    145 -> 77
    146 -> 154
    147 -> 41
    148 -> 82
    149 -> 164
    150 -> 85
    151 -> 170
    152 -> 73
    153 -> 146
    154 -> 57
    155 -> 114
    156 -> 228
    157 -> 213
    158 -> 183
    159 -> 115
    160 -> 230
    161 -> 209
    162 -> 191
    163 -> 99
    164 -> 198
    165 -> 145
    166 -> 63
    167 -> 126
    168 -> 252
    169 -> 229
    170 -> 215
    171 -> 179
    172 -> 123
    173 -> 246
    174 -> 241
    175 -> 255
    176 -> 227
    177 -> 219
    178 -> 171
    179 -> 75
    180 -> 150
    181 -> 49
    182 -> 98
    183 -> 196
    184 -> 149
    185 -> 55
    186 -> 110
    187 -> 220
    188 -> 165
    189 -> 87
    190 -> 174
    191 -> 65
    192 -> 130
    193 -> 25
    194 -> 50
    195 -> 100
    196 -> 200
    197 -> 141
    198 -> 7
    199 -> 14
    200 -> 28
    201 -> 56
    202 -> 112
    203 -> 224
    204 -> 221
    205 -> 167
    206 -> 83
    207 -> 166
    208 -> 81
    209 -> 162
    210 -> 89
    211 -> 178
    212 -> 121
    213 -> 242
    214 -> 249
    215 -> 239
    216 -> 195
    217 -> 155
    218 -> 43
    219 -> 86
    220 -> 172
    221 -> 69
    222 -> 138
    223 -> 9
    224 -> 18
    225 -> 36
    226 -> 72
    227 -> 144
    228 -> 61
    229 -> 122
    230 -> 244
    231 -> 245
    232 -> 247
    233 -> 243
    234 -> 251
    235 -> 235
    236 -> 203
    237 -> 139
    238 -> 11
    239 -> 22
    240 -> 44
    241 -> 88
    242 -> 176
    243 -> 125
    244 -> 250
    245 -> 233
    246 -> 207
    247 -> 131
    248 -> 27
    249 -> 54
    250 -> 108
    251 -> 216
    252 -> 173
    253 -> 71
    254 -> 142
    _ -> 1
  }
}

fn gf_log(v: Int) -> Int {
  case v {
    1 -> 0
    2 -> 1
    3 -> 25
    4 -> 2
    5 -> 50
    6 -> 26
    7 -> 198
    8 -> 3
    9 -> 223
    10 -> 51
    11 -> 238
    12 -> 27
    13 -> 104
    14 -> 199
    15 -> 75
    16 -> 4
    17 -> 100
    18 -> 224
    19 -> 14
    20 -> 52
    21 -> 141
    22 -> 239
    23 -> 129
    24 -> 28
    25 -> 193
    26 -> 105
    27 -> 248
    28 -> 200
    29 -> 8
    30 -> 76
    31 -> 113
    32 -> 5
    33 -> 138
    34 -> 101
    35 -> 47
    36 -> 225
    37 -> 36
    38 -> 15
    39 -> 33
    40 -> 53
    41 -> 147
    42 -> 142
    43 -> 218
    44 -> 240
    45 -> 18
    46 -> 130
    47 -> 69
    48 -> 29
    49 -> 181
    50 -> 194
    51 -> 125
    52 -> 106
    53 -> 39
    54 -> 249
    55 -> 185
    56 -> 201
    57 -> 154
    58 -> 9
    59 -> 120
    60 -> 77
    61 -> 228
    62 -> 114
    63 -> 166
    64 -> 6
    65 -> 191
    66 -> 139
    67 -> 98
    68 -> 102
    69 -> 221
    70 -> 48
    71 -> 253
    72 -> 226
    73 -> 152
    74 -> 37
    75 -> 179
    76 -> 16
    77 -> 145
    78 -> 34
    79 -> 136
    80 -> 54
    81 -> 208
    82 -> 148
    83 -> 206
    84 -> 143
    85 -> 150
    86 -> 219
    87 -> 189
    88 -> 241
    89 -> 210
    90 -> 19
    91 -> 92
    92 -> 131
    93 -> 56
    94 -> 70
    95 -> 64
    96 -> 30
    97 -> 66
    98 -> 182
    99 -> 163
    100 -> 195
    101 -> 72
    102 -> 126
    103 -> 110
    104 -> 107
    105 -> 58
    106 -> 40
    107 -> 84
    108 -> 250
    109 -> 133
    110 -> 186
    111 -> 61
    112 -> 202
    113 -> 94
    114 -> 155
    115 -> 159
    116 -> 10
    117 -> 21
    118 -> 121
    119 -> 43
    120 -> 78
    121 -> 212
    122 -> 229
    123 -> 172
    124 -> 115
    125 -> 243
    126 -> 167
    127 -> 87
    128 -> 7
    129 -> 112
    130 -> 192
    131 -> 247
    132 -> 140
    133 -> 128
    134 -> 99
    135 -> 13
    136 -> 103
    137 -> 74
    138 -> 222
    139 -> 237
    140 -> 49
    141 -> 197
    142 -> 254
    143 -> 24
    144 -> 227
    145 -> 165
    146 -> 153
    147 -> 119
    148 -> 38
    149 -> 184
    150 -> 180
    151 -> 124
    152 -> 17
    153 -> 68
    154 -> 146
    155 -> 217
    156 -> 35
    157 -> 32
    158 -> 137
    159 -> 46
    160 -> 55
    161 -> 63
    162 -> 209
    163 -> 91
    164 -> 149
    165 -> 188
    166 -> 207
    167 -> 205
    168 -> 144
    169 -> 135
    170 -> 151
    171 -> 178
    172 -> 220
    173 -> 252
    174 -> 190
    175 -> 97
    176 -> 242
    177 -> 86
    178 -> 211
    179 -> 171
    180 -> 20
    181 -> 42
    182 -> 93
    183 -> 158
    184 -> 132
    185 -> 60
    186 -> 57
    187 -> 83
    188 -> 71
    189 -> 109
    190 -> 65
    191 -> 162
    192 -> 31
    193 -> 45
    194 -> 67
    195 -> 216
    196 -> 183
    197 -> 123
    198 -> 164
    199 -> 118
    200 -> 196
    201 -> 23
    202 -> 73
    203 -> 236
    204 -> 127
    205 -> 12
    206 -> 111
    207 -> 246
    208 -> 108
    209 -> 161
    210 -> 59
    211 -> 82
    212 -> 41
    213 -> 157
    214 -> 85
    215 -> 170
    216 -> 251
    217 -> 96
    218 -> 134
    219 -> 177
    220 -> 187
    221 -> 204
    222 -> 62
    223 -> 90
    224 -> 203
    225 -> 89
    226 -> 95
    227 -> 176
    228 -> 156
    229 -> 169
    230 -> 160
    231 -> 81
    232 -> 11
    233 -> 245
    234 -> 22
    235 -> 235
    236 -> 122
    237 -> 117
    238 -> 44
    239 -> 215
    240 -> 79
    241 -> 174
    242 -> 213
    243 -> 233
    244 -> 230
    245 -> 231
    246 -> 173
    247 -> 232
    248 -> 116
    249 -> 214
    250 -> 244
    251 -> 234
    252 -> 168
    253 -> 80
    254 -> 88
    255 -> 175
    _ -> 0
  }
}

fn matrix_new(size: Int) -> Matrix {
  Matrix(size: size, modules: dict.new(), function_modules: dict.new())
}

fn matrix_set(
  matrix: Matrix,
  row: Int,
  col: Int,
  value: Bool,
  is_function: Bool,
) -> Matrix {
  let modules = dict.insert(matrix.modules, #(row, col), value)
  let function_modules = case is_function {
    True -> dict.insert(matrix.function_modules, #(row, col), Nil)
    False -> matrix.function_modules
  }
  Matrix(..matrix, modules: modules, function_modules: function_modules)
}

fn matrix_get(matrix: Matrix, row: Int, col: Int) -> Bool {
  case dict.get(matrix.modules, #(row, col)) {
    Ok(v) -> v
    Error(_) -> False
  }
}

fn matrix_is_function(matrix: Matrix, row: Int, col: Int) -> Bool {
  dict.has_key(matrix.function_modules, #(row, col))
}

fn range_list(from: Int, to_inclusive: Int) -> List(Int) {
  case from > to_inclusive {
    True -> []
    False -> [from, ..range_list(from + 1, to_inclusive)]
  }
}

fn place_function_patterns(matrix: Matrix, version: Version) -> Matrix {
  matrix
  |> place_finder_patterns()
  |> place_alignment_patterns(version)
  |> place_timing_patterns()
  |> place_dark_module(version)
}

fn place_finder_pattern(matrix: Matrix, row_off: Int, col_off: Int) -> Matrix {
  list.fold(range_list(0, 6), matrix, fn(mat, r) {
    list.fold(range_list(0, 6), mat, fn(m, c) {
      let dark = case r, c {
        0, _ | 6, _ -> True
        _, 0 | _, 6 -> True
        r, c if r >= 2 && r <= 4 && c >= 2 && c <= 4 -> True
        _, _ -> False
      }
      matrix_set(m, row_off + r, col_off + c, dark, True)
    })
  })
}

fn place_finder_patterns(matrix: Matrix) -> Matrix {
  let n = matrix.size
  let mat =
    matrix
    |> place_finder_pattern(0, 0)
    |> place_finder_pattern(0, n - 7)
    |> place_finder_pattern(n - 7, 0)
  list.fold(range_list(0, 7), mat, fn(m, i) {
    let m = matrix_set(m, i, 7, False, True)
    let m = matrix_set(m, 7, i, False, True)
    let m = matrix_set(m, i, n - 8, False, True)
    let m = matrix_set(m, 7, n - 8 + i, False, True)
    let m = matrix_set(m, n - 8, i, False, True)
    matrix_set(m, n - 8 + i, 7, False, True)
  })
}

fn place_timing_patterns(matrix: Matrix) -> Matrix {
  let n = matrix.size
  list.fold(range_list(8, n - 9), matrix, fn(m, i) {
    let dark = i % 2 == 0
    let m = case matrix_is_function(m, 6, i) {
      True -> m
      False -> matrix_set(m, 6, i, dark, True)
    }
    case matrix_is_function(m, i, 6) {
      True -> m
      False -> matrix_set(m, i, 6, dark, True)
    }
  })
}

fn alignment_centers(version: Version) -> List(Int) {
  let Version(v) = version
  case v {
    1 -> []
    2 -> [6, 18]
    3 -> [6, 22]
    4 -> [6, 26]
    5 -> [6, 30]
    6 -> [6, 34]
    7 -> [6, 22, 38]
    8 -> [6, 24, 42]
    9 -> [6, 26, 46]
    10 -> [6, 28, 50]
    11 -> [6, 30, 54]
    12 -> [6, 32, 58]
    13 -> [6, 34, 62]
    14 -> [6, 26, 46, 66]
    15 -> [6, 26, 48, 70]
    16 -> [6, 26, 50, 74]
    17 -> [6, 30, 50, 74]
    18 -> [6, 30, 56, 82]
    19 -> [6, 30, 58, 86]
    20 -> [6, 34, 62, 90]
    21 -> [6, 28, 50, 72, 94]
    22 -> [6, 26, 50, 74, 98]
    23 -> [6, 30, 54, 78, 102]
    24 -> [6, 28, 54, 80, 106]
    25 -> [6, 32, 58, 84, 110]
    26 -> [6, 30, 58, 86, 114]
    27 -> [6, 34, 62, 90, 118]
    28 -> [6, 26, 50, 74, 98, 122]
    29 -> [6, 30, 54, 78, 102, 126]
    30 -> [6, 26, 52, 78, 104, 130]
    31 -> [6, 30, 56, 82, 108, 134]
    32 -> [6, 34, 60, 86, 112, 138]
    33 -> [6, 30, 58, 86, 114, 142]
    34 -> [6, 34, 62, 90, 118, 146]
    35 -> [6, 30, 54, 78, 102, 126, 150]
    36 -> [6, 24, 50, 76, 102, 128, 154]
    37 -> [6, 28, 54, 80, 106, 132, 158]
    38 -> [6, 32, 58, 84, 110, 136, 162]
    39 -> [6, 26, 54, 82, 110, 138, 166]
    40 -> [6, 30, 58, 86, 114, 142, 170]
    _ -> []
  }
}

fn place_alignment_patterns(matrix: Matrix, version: Version) -> Matrix {
  let n = matrix.size
  let centers = alignment_centers(version)
  list.fold(centers, matrix, fn(mat, r) {
    list.fold(centers, mat, fn(m, c) {
      let overlaps_finder =
        { r <= 8 && c <= 8 }
        || { r <= 8 && c >= n - 8 }
        || { r >= n - 8 && c <= 8 }
      case overlaps_finder {
        True -> m
        False ->
          list.fold(range_list(-2, 2), m, fn(m2, dr) {
            list.fold(range_list(-2, 2), m2, fn(m3, dc) {
              let dark =
                int.absolute_value(dr) == 2
                || int.absolute_value(dc) == 2
                || { dr == 0 && dc == 0 }
              matrix_set(m3, r + dr, c + dc, dark, True)
            })
          })
      }
    })
  })
}

fn place_dark_module(matrix: Matrix, version: Version) -> Matrix {
  let Version(v) = version
  let row = 4 * v + 9
  matrix_set(matrix, row, 8, True, True)
}

fn reserve_format_areas(matrix: Matrix) -> Matrix {
  let n = matrix.size
  let mat =
    list.fold(range_list(0, 8), matrix, fn(m, i) {
      let m = case matrix_is_function(m, 8, i) {
        True -> m
        False -> matrix_set(m, 8, i, False, True)
      }
      case i < 8 {
        True ->
          case matrix_is_function(m, i, 8) {
            True -> m
            False -> matrix_set(m, i, 8, False, True)
          }
        False -> m
      }
    })
  list.fold(range_list(0, 7), mat, fn(m, i) {
    let m = case matrix_is_function(m, 8, n - 8 + i) {
      True -> m
      False -> matrix_set(m, 8, n - 8 + i, False, True)
    }
    case matrix_is_function(m, n - 7 + i, 8) {
      True -> m
      False -> matrix_set(m, n - 7 + i, 8, False, True)
    }
  })
}

fn reserve_version_areas(matrix: Matrix, version: Version) -> Matrix {
  let Version(v) = version
  case v >= 7 {
    False -> matrix
    True -> {
      let n = matrix.size
      list.fold(range_list(0, 5), matrix, fn(m, i) {
        list.fold(range_list(0, 2), m, fn(m2, j) {
          let m2 = matrix_set(m2, n - 11 + j, i, False, True)
          matrix_set(m2, i, n - 11 + j, False, True)
        })
      })
    }
  }
}

fn bit_length(n: Int) -> Int {
  bit_length_loop(n, 0)
}

fn bit_length_loop(n: Int, count: Int) -> Int {
  case n {
    0 -> count
    _ -> bit_length_loop(int.bitwise_shift_right(n, 1), count + 1)
  }
}

fn compute_format_bits(level: ErrorCorrectionLevel, mask: Int) -> Int {
  let level_bits = case level {
    L -> 1
    M -> 0
    Q -> 3
    H -> 2
  }
  let data = int.bitwise_or(int.bitwise_shift_left(level_bits, 3), mask)
  let generator = 0x537
  let remainder = bch_remainder(data, 10, generator)
  let format_bits = int.bitwise_or(int.bitwise_shift_left(data, 10), remainder)
  int.bitwise_exclusive_or(format_bits, 0x5412)
}

fn compute_version_bits(version: Version) -> Int {
  let Version(v) = version
  let generator = 0x1F25
  let remainder = bch_remainder(v, 12, generator)
  int.bitwise_or(int.bitwise_shift_left(v, 12), remainder)
}

fn bch_remainder(data: Int, num_check_bits: Int, generator: Int) -> Int {
  let shifted = int.bitwise_shift_left(data, num_check_bits)
  let gen_len = bit_length(generator)
  bch_remainder_loop(shifted, generator, gen_len, bit_length(shifted))
}

fn bch_remainder_loop(
  value: Int,
  generator: Int,
  gen_len: Int,
  val_len: Int,
) -> Int {
  case val_len >= gen_len {
    False -> value
    True -> {
      let shifted_gen = int.bitwise_shift_left(generator, val_len - gen_len)
      let new_value = int.bitwise_exclusive_or(value, shifted_gen)
      bch_remainder_loop(new_value, generator, gen_len, bit_length(new_value))
    }
  }
}

fn bitarray_to_bool_list(bits: BitArray) -> List(Bool) {
  bitarray_to_bool_list_loop(bits, [])
  |> list.reverse
}

fn bitarray_to_bool_list_loop(bits: BitArray, acc: List(Bool)) -> List(Bool) {
  case bits {
    <<b:size(1), rest:bits>> ->
      bitarray_to_bool_list_loop(rest, [b == 1, ..acc])
    _ -> acc
  }
}

fn zigzag_coords(n: Int) -> List(#(Int, Int)) {
  zigzag_coords_loop(n, n - 1, True, [])
}

fn zigzag_coords_loop(
  n: Int,
  right_col: Int,
  going_up: Bool,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case right_col < 0 {
    True -> acc
    False -> {
      let right_col = case right_col == 6 {
        True -> 5
        False -> right_col
      }
      let left_col = right_col - 1
      let rows = case going_up {
        True -> range_list(0, n - 1) |> list.reverse
        False -> range_list(0, n - 1)
      }
      let new_coords =
        list.flat_map(rows, fn(row) {
          case left_col >= 0 {
            True -> [#(row, right_col), #(row, left_col)]
            False -> [#(row, right_col)]
          }
        })
      zigzag_coords_loop(
        n,
        right_col - 2,
        !going_up,
        list.append(acc, new_coords),
      )
    }
  }
}

fn place_data_bits(matrix: Matrix, data: BitArray) -> Matrix {
  let n = matrix.size
  let coords = zigzag_coords(n)
  let data_bits = bitarray_to_bool_list(data)
  let available =
    list.filter(coords, fn(coord) {
      let #(r, c) = coord
      !matrix_is_function(matrix, r, c)
    })
  place_data_bits_loop(matrix, available, data_bits)
}

fn place_data_bits_loop(
  matrix: Matrix,
  coords: List(#(Int, Int)),
  bits: List(Bool),
) -> Matrix {
  case coords, bits {
    [#(r, c), ..rest_coords], [b, ..rest_bits] ->
      place_data_bits_loop(
        matrix_set(matrix, r, c, b, False),
        rest_coords,
        rest_bits,
      )
    _, _ -> matrix
  }
}

fn mask_condition(mask: Int, row: Int, col: Int) -> Bool {
  case mask {
    0 -> { row + col } % 2 == 0
    1 -> row % 2 == 0
    2 -> col % 3 == 0
    3 -> { row + col } % 3 == 0
    4 -> { row / 2 + col / 3 } % 2 == 0
    5 -> { row * col } % 2 + { row * col } % 3 == 0
    6 -> { { row * col } % 2 + { row * col } % 3 } % 2 == 0
    7 -> { { row + col } % 2 + { row * col } % 3 } % 2 == 0
    _ -> False
  }
}

fn find_best_mask_and_render(
  matrix: Matrix,
  version: Version,
  level: ErrorCorrectionLevel,
) -> Qr {
  let n = matrix.size
  // Convert to fast list representation once
  let base_rows = matrix_to_rows_bool(matrix)
  let func_rows = matrix_to_function_rows(matrix)

  // Find best mask using fast operations
  let best_mask =
    find_best_mask_fast(base_rows, func_rows, n, version, level, 0, -1, 0)

  // Apply best mask and render directly to output (skip Dict operations)
  let final_rows =
    apply_mask_fast(base_rows, func_rows, best_mask)
    |> write_format_info_fast(n, level, best_mask)
    |> write_version_info_fast(n, version)

  Qr(n, final_rows)
}

fn matrix_to_rows_bool(matrix: Matrix) -> List(List(Bool)) {
  let n = matrix.size
  list.map(range_list(0, n - 1), fn(r) {
    list.map(range_list(0, n - 1), fn(c) { matrix_get(matrix, r, c) })
  })
}

fn matrix_to_function_rows(matrix: Matrix) -> List(List(Bool)) {
  let n = matrix.size
  list.map(range_list(0, n - 1), fn(r) {
    list.map(range_list(0, n - 1), fn(c) { matrix_is_function(matrix, r, c) })
  })
}

fn find_best_mask_fast(
  base_rows: List(List(Bool)),
  func_rows: List(List(Bool)),
  n: Int,
  version: Version,
  level: ErrorCorrectionLevel,
  mask: Int,
  best_score: Int,
  best_mask: Int,
) -> Int {
  case mask > 7 {
    True -> best_mask
    False -> {
      let candidate_rows =
        apply_mask_fast(base_rows, func_rows, mask)
        |> write_format_info_fast(n, level, mask)
        |> write_version_info_fast(n, version)
      let score = compute_penalty_fast(candidate_rows)
      case best_score < 0 || score < best_score {
        True ->
          find_best_mask_fast(
            base_rows,
            func_rows,
            n,
            version,
            level,
            mask + 1,
            score,
            mask,
          )
        False ->
          find_best_mask_fast(
            base_rows,
            func_rows,
            n,
            version,
            level,
            mask + 1,
            best_score,
            best_mask,
          )
      }
    }
  }
}

fn apply_mask_fast(
  base_rows: List(List(Bool)),
  func_rows: List(List(Bool)),
  mask: Int,
) -> List(List(Bool)) {
  list.index_map(list.zip(base_rows, func_rows), fn(row_pair, r) {
    let #(mod_row, func_row) = row_pair
    list.index_map(list.zip(mod_row, func_row), fn(cell_pair, c) {
      let #(value, is_func) = cell_pair
      case is_func {
        True -> value
        False ->
          case mask_condition(mask, r, c) {
            True -> !value
            False -> value
          }
      }
    })
  })
}

fn write_format_info_fast(
  rows: List(List(Bool)),
  n: Int,
  level: ErrorCorrectionLevel,
  mask: Int,
) -> List(List(Bool)) {
  let bits = compute_format_bits(level, mask)
  // Write format bits to both copies
  rows
  |> set_fast(8, 0, get_int_bit(bits, 14))
  |> set_fast(8, 1, get_int_bit(bits, 13))
  |> set_fast(8, 2, get_int_bit(bits, 12))
  |> set_fast(8, 3, get_int_bit(bits, 11))
  |> set_fast(8, 4, get_int_bit(bits, 10))
  |> set_fast(8, 5, get_int_bit(bits, 9))
  |> set_fast(8, 7, get_int_bit(bits, 8))
  |> set_fast(8, 8, get_int_bit(bits, 7))
  |> set_fast(7, 8, get_int_bit(bits, 6))
  |> set_fast(5, 8, get_int_bit(bits, 5))
  |> set_fast(4, 8, get_int_bit(bits, 4))
  |> set_fast(3, 8, get_int_bit(bits, 3))
  |> set_fast(2, 8, get_int_bit(bits, 2))
  |> set_fast(1, 8, get_int_bit(bits, 1))
  |> set_fast(0, 8, get_int_bit(bits, 0))
  // Second copy
  |> set_fast(n - 1, 8, get_int_bit(bits, 14))
  |> set_fast(n - 2, 8, get_int_bit(bits, 13))
  |> set_fast(n - 3, 8, get_int_bit(bits, 12))
  |> set_fast(n - 4, 8, get_int_bit(bits, 11))
  |> set_fast(n - 5, 8, get_int_bit(bits, 10))
  |> set_fast(n - 6, 8, get_int_bit(bits, 9))
  |> set_fast(n - 7, 8, get_int_bit(bits, 8))
  |> set_fast(8, n - 8, get_int_bit(bits, 7))
  |> set_fast(8, n - 7, get_int_bit(bits, 6))
  |> set_fast(8, n - 6, get_int_bit(bits, 5))
  |> set_fast(8, n - 5, get_int_bit(bits, 4))
  |> set_fast(8, n - 4, get_int_bit(bits, 3))
  |> set_fast(8, n - 3, get_int_bit(bits, 2))
  |> set_fast(8, n - 2, get_int_bit(bits, 1))
  |> set_fast(8, n - 1, get_int_bit(bits, 0))
}

fn write_version_info_fast(
  rows: List(List(Bool)),
  n: Int,
  version: Version,
) -> List(List(Bool)) {
  let Version(v) = version
  case v >= 7 {
    False -> rows
    True -> {
      let bits = compute_version_bits(version)
      write_version_bits_fast(rows, n, bits, 0)
    }
  }
}

fn write_version_bits_fast(
  rows: List(List(Bool)),
  n: Int,
  bits: Int,
  i: Int,
) -> List(List(Bool)) {
  case i > 17 {
    True -> rows
    False -> {
      let bit_val = int.bitwise_and(int.bitwise_shift_right(bits, i), 1) == 1
      let col = i / 3
      let row = i % 3
      rows
      |> set_fast(n - 11 + row, col, bit_val)
      |> set_fast(col, n - 11 + row, bit_val)
      |> write_version_bits_fast(n, bits, i + 1)
    }
  }
}

fn get_int_bit(bits: Int, pos: Int) -> Bool {
  int.bitwise_and(int.bitwise_shift_right(bits, pos), 1) == 1
}

fn set_fast(
  rows: List(List(Bool)),
  row: Int,
  col: Int,
  value: Bool,
) -> List(List(Bool)) {
  list.index_map(rows, fn(r, ri) {
    case ri == row {
      True ->
        list.index_map(r, fn(cell, ci) {
          case ci == col {
            True -> value
            False -> cell
          }
        })
      False -> r
    }
  })
}

fn compute_penalty_fast(rows: List(List(Bool))) -> Int {
  let n = list.length(rows)

  // Single pass over rows: horizontal runs, finder patterns, dark count, blocks
  let #(h_runs, h_finder, dark_count, blocks) =
    process_rows_combined(rows, [], 0, 0, 0, 0)

  // Single transpose (was being done twice before!)
  let columns = list.transpose(rows)

  // Process columns for vertical runs and finder patterns in one pass
  let columns_to_check = list.take(columns, n - 10)
  let remaining_columns = list.drop(columns, n - 10)

  // Columns that need finder pattern checking (with padding)
  let #(v_runs_partial, v_finder) =
    process_columns_with_finder(columns_to_check, n, 0, 0)

  // Remaining columns only need runs
  let v_runs_rest =
    list.fold(remaining_columns, 0, fn(acc, col) {
      acc + penalty_line_runs(col)
    })

  let v_runs = v_runs_partial + v_runs_rest

  // Balance calculation
  let total_modules = n * n
  let percentage = dark_count * 100 / total_modules
  let prev_five = percentage - percentage % 5
  let next_five = prev_five + 5
  let deviation1 = int.absolute_value(prev_five - 50) / 5
  let deviation2 = int.absolute_value(next_five - 50) / 5
  let balance = case deviation1 < deviation2 {
    True -> deviation1 * 10
    False -> deviation2 * 10
  }

  h_runs + v_runs + blocks + h_finder + v_finder + balance
}

fn process_rows_combined(
  rows: List(List(Bool)),
  prev_row: List(Bool),
  h_runs: Int,
  h_finder: Int,
  dark_count: Int,
  blocks: Int,
) -> #(Int, Int, Int, Int) {
  case rows {
    [] -> #(h_runs, h_finder, dark_count, blocks)
    [row, ..rest] -> {
      let row_runs = penalty_line_runs(row)
      let row_finder = check_finder_patterns_in_line(row)
      let row_darks = count_true(row, 0)
      let row_blocks = case prev_row {
        [] -> 0
        _ -> penalty_blocks_row_pair(prev_row, row, 0)
      }
      process_rows_combined(
        rest,
        row,
        h_runs + row_runs,
        h_finder + row_finder,
        dark_count + row_darks,
        blocks + row_blocks,
      )
    }
  }
}

fn count_true(row: List(Bool), acc: Int) -> Int {
  case row {
    [] -> acc
    [True, ..rest] -> count_true(rest, acc + 1)
    [False, ..rest] -> count_true(rest, acc)
  }
}

fn process_columns_with_finder(
  columns: List(List(Bool)),
  n: Int,
  runs_acc: Int,
  finder_acc: Int,
) -> #(Int, Int) {
  case columns {
    [] -> #(runs_acc, finder_acc)
    [col, ..rest] -> {
      let col_runs = penalty_line_runs(col)
      // Pad column for finder pattern check
      let padded =
        list.append(col, [
          False,
          False,
          False,
          False,
          False,
          False,
          False,
          False,
          False,
          False,
        ])
      let col_finder = check_finder_patterns_in_line_n(padded, n)
      process_columns_with_finder(
        rest,
        n,
        runs_acc + col_runs,
        finder_acc + col_finder,
      )
    }
  }
}

fn penalty_line_runs(line: List(Bool)) -> Int {
  penalty_line_runs_loop(line, False, 0, 0)
}

fn penalty_line_runs_loop(
  line: List(Bool),
  last_color: Bool,
  run_length: Int,
  acc: Int,
) -> Int {
  case line {
    [] ->
      case run_length >= 5 {
        True -> acc + 3 + run_length - 5
        False -> acc
      }
    [color, ..rest] ->
      case run_length == 0 {
        True -> penalty_line_runs_loop(rest, color, 1, acc)
        False ->
          case color == last_color {
            True -> penalty_line_runs_loop(rest, color, run_length + 1, acc)
            False -> {
              let penalty = case run_length >= 5 {
                True -> 3 + run_length - 5
                False -> 0
              }
              penalty_line_runs_loop(rest, color, 1, acc + penalty)
            }
          }
      }
  }
}

fn penalty_blocks_row_pair(row1: List(Bool), row2: List(Bool), acc: Int) -> Int {
  case row1, row2 {
    [a, b, ..rest1], [c, d, ..rest2] -> {
      let penalty = case a == b && a == c && a == d {
        True -> 3
        False -> 0
      }
      penalty_blocks_row_pair([b, ..rest1], [d, ..rest2], acc + penalty)
    }
    _, _ -> acc
  }
}

fn check_finder_patterns_in_line_n(line: List(Bool), n: Int) -> Int {
  check_finder_sliding_n(line, 0, n)
}

fn check_finder_sliding_n(line: List(Bool), pos: Int, n: Int) -> Int {
  case pos >= n {
    True -> 0
    False ->
      case line {
        [a, b, c, d, e, f, g, h, i, j, k, ..rest] -> {
          let matches_a =
            a == True
            && b == False
            && c == True
            && d == True
            && e == True
            && f == False
            && g == True
            && h == False
            && i == False
            && j == False
            && k == False
          let matches_b =
            a == False
            && b == False
            && c == False
            && d == False
            && e == True
            && f == False
            && g == True
            && h == True
            && i == True
            && j == False
            && k == True
          let penalty = case matches_a || matches_b {
            True -> 40
            False -> 0
          }
          penalty
          + check_finder_sliding_n(
            [b, c, d, e, f, g, h, i, j, k, ..rest],
            pos + 1,
            n,
          )
        }
        _ -> 0
      }
  }
}

fn check_finder_patterns_in_line(line: List(Bool)) -> Int {
  check_finder_sliding(line, 0)
}

fn check_finder_sliding(line: List(Bool), acc: Int) -> Int {
  case line {
    [a, b, c, d, e, f, g, h, i, j, k, ..rest] -> {
      // Pattern A: 1,0,1,1,1,0,1,0,0,0,0 (True=dark)
      // Pattern B: 0,0,0,0,1,0,1,1,1,0,1
      let matches_a =
        a == True
        && b == False
        && c == True
        && d == True
        && e == True
        && f == False
        && g == True
        && h == False
        && i == False
        && j == False
        && k == False
      let matches_b =
        a == False
        && b == False
        && c == False
        && d == False
        && e == True
        && f == False
        && g == True
        && h == True
        && i == True
        && j == False
        && k == True
      let penalty = case matches_a || matches_b {
        True -> 40
        False -> 0
      }
      check_finder_sliding(
        [b, c, d, e, f, g, h, i, j, k, ..rest],
        acc + penalty,
      )
    }
    _ -> acc
  }
}
