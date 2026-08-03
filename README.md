# glqr

[![Package Version](https://img.shields.io/hexpm/v/glqr)](https://hex.pm/packages/glqr)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glqr/)

```sh
gleam add glqr
```
## Display QR Code
```gleam
import glqr as qr

pub fn main() -> Nil {
  let assert Ok(code) =
    qr.new("HELLO WORLD")
    |> qr.generate()

  qr.print(code)
}
```

If you need the string itself use `qr.to_printable()`, but print it with
`io.println` because `echo` escapes the newlines and mangles the output.

## Config Options

- Error Correction Level
    - L (Low, 7% of damage to image be restored)
    - M (Medium, 15% of damage to image be restored)
    - Q (Quartile, 25% of damage to image be restored)
    - H (High, 30% of damage to image be restored)

- Minimum Version (1-40, default is 1)
    - Version 1: 21x21 matrix
    - Version 40: 177x177 matrix

```gleam
import glqr as qr

pub fn main() -> Nil {
  let assert Ok(code) =
    qr.new("HELLO WORLD")
    |> qr.error_correction(qr.L)
    |> qr.min_version(10)
    |> qr.generate()

  qr.print(code)
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

## Simple Lustre Example
```gleam
import gleam/int
import glqr
import lustre
import lustre/attribute
import lustre/element

fn render_qr(value: String, size: Int) {
  let assert Ok(matrix) =
    glqr.new(value)
    |> glqr.generate()

  let svg = glqr.to_svg(matrix)

  lustre.element(element.unsafe_raw_html(
    "",
    "div",
    [attribute.style("max-width", int.to_string(size) <> "px")],
    svg,
  ))
}

pub fn main() {
  let app = render_qr("https://github.com/lustre-labs/lustre", 150)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}
````

## Standard Content Formats
Builders for common QR code payload formats — WiFi networks, contact cards
(vCard), calendar events, email, SMS, phone numbers, and geo locations.
Plain URLs need no helper, pass them directly to `glqr.new`.

```gleam
import glqr as qr

pub fn main() -> Nil {
  // Join a WiFi network
  let wifi =
    qr.wifi(
      ssid: "MyNetwork",
      authentication: qr.Wpa("hunter2"),
      hidden: False,
    )

  // Share contact info
  let card =
    qr.v_card(name: "Lucy Gleam")
    |> qr.v_card_phone("+461234567")
    |> qr.v_card_email("lucy@gleam.run")
    |> qr.v_card_website("https://gleam.run")
    |> qr.v_card_to_string

  // Other formats
  let _event =
    qr.calendar_event(
      summary: "Gleam meetup",
      starts_at: "20260719T093000Z",
      ends_at: "20260719T103000Z",
    )
    |> qr.calendar_event_to_string
  let _email = qr.email("hello@example.com")
  let _sms = qr.sms(number: "+461234567", message: "Hello!")
  let _phone = qr.phone("+461234567")
  let _geo = qr.geo(latitude: 59.3293, longitude: 18.0686)

  let assert Ok(code) = qr.new(wifi) |> qr.generate()
  qr.print(code)

  let assert Ok(code) = qr.new(card) |> qr.generate()
  qr.print(code)
}
```

Further documentation can be found at <https://hexdocs.pm/glqr>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

### Benchmark

A small benchmark of `glqr.generate` lives in `dev/bench.gleam`, powered by
[gleamy_bench](https://hex.pm/packages/gleamy_bench). It works on both targets:

```sh
gleam run -m bench                      # Erlang target
gleam run -m bench --target javascript
```

Sample output on an Apple M4 machine (Erlang target). IPS is QR codes
generated per second, Min/P99 are milliseconds per QR code:

```
Input               Function                       IPS           Min           P99
v1 (11 chars)       glqr.generate            3669.1609        0.2379        0.3329
v10 (500 chars)     glqr.generate             231.1611        3.7884        4.8095
v40 (4200 chars)    glqr.generate              37.5127       25.5247       27.5804
```

## TODO
- [x] Import as local module
- [x] Data Analysis
    - [x] Numeric
    - [x] Alphanumeric
    - [x] Byte
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
- [x] Add more Snapshot testing
- [x] Add Lustre example
- [x] Add opaque Qr type with `to_bits` BitArray view
- [x] Add to_bits feature
- [x] Add convenience functions
    - [x] Contact Info (vCard)
    - [x] WiFi Network
    - [x] Url (no helper needed, pass URLs directly to `glqr.new`)
    - [x] Email
    - [x] Calendar Event
    - [x] SMS
    - [x] Phone Number
    - [x] GeoLocation

## References
[Thonky's QR Code Tutorial](https://www.thonky.com/qr-code-tutorial)

[IODevs elixir qr code library](https://github.com/iodevs/qr_code)

[SiliconJungles elixir qr code library](https://github.com/SiliconJungles/eqrcode)

[Nayuki QR Code Step by Step](https://www.nayuki.io/page/creating-a-qr-code-step-by-step)

[Gears BitArray Blog Post](https://gearsco.de/blog/bit-array-syntax/)
