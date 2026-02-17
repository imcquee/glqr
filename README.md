# glqr

[![Package Version](https://img.shields.io/hexpm/v/glqr)](https://hex.pm/packages/glqr)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glqr/)

```sh
gleam add glqr@1
```
## Display QR Code
```gleam
import gleam/io
import glqr as qr

pub fn main() -> Nil {
  let assert Ok(code) =
    qr.new("HELLO WORLD")
    |> qr.generate()

  code
  |> qr.to_printable()
  |> io.println() // YOU CANT USE ECHO AS IT PRESERVES THE NEWLINE
}
```

## Config Options
```gleam
import gleam/io
import glqr as qr

pub fn main() -> Nil {
  let assert Ok(code) =
    qr.new("HELLO WORLD")
    |> qr.error_correction(qr.L)
    |> qr.min_version(10)
    |> qr.generate()

  code
  |> qr.to_printable()
  |> io.println() // YOU CANT USE ECHO AS IT PRESERVES THE NEWLINE
}
```

## Save SVG
```gleam
import glqr as qr
import simplifile

pub fn main() -> Nil {
  let assert Ok(code) =
    qr.new("HELLO WORLD")
    |> qr.generate()

  let svg =
    code
    |> qr.to_svg()

  let assert Ok(_) = simplifile.write("output.svg", svg)
  Nil
}
```

Further documentation can be found at <https://hexdocs.pm/glqr>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## TODO
- [x] Import as local module
- [x] Data Analysis
    - [x] Numeric
    - [x] Alphanumeric
    - [x] Byte
    - [ ] Kanji
- [x] Data Encoding
    - [x] Mode Indicator
    - [x] Character Count Indicator
    - [x] Data Bits
    - [x] Terminator
    - [x] Pad Bits
- [x] Error correction
- [x] QR Code Structure
- [x] Draw Matrix
- [x] Add Snapshot Testing

## References
[Thonky's QR Code Tutorial](https://www.thonky.com/qr-code-tutorial)
