import birdie
import gleam/string
import gleeunit
import gleeunit/should
import glqr

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_world_printable_test() {
  let assert Ok(matrix) = glqr.new("HELLO WORLD") |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD printable")
}

pub fn hello_world_svg_test() {
  let assert Ok(matrix) = glqr.new("HELLO WORLD") |> glqr.generate
  matrix
  |> glqr.to_svg
  |> birdie.snap(title: "HELLO WORLD svg")
}

pub fn hello_world_ec_l_printable_test() {
  let assert Ok(matrix) =
    glqr.new("HELLO WORLD")
    |> glqr.error_correction(glqr.L)
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD EC-L printable")
}

pub fn hello_world_ec_q_printable_test() {
  let assert Ok(matrix) =
    glqr.new("HELLO WORLD")
    |> glqr.error_correction(glqr.Q)
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD EC-Q printable")
}

pub fn hello_world_ec_h_printable_test() {
  let assert Ok(matrix) =
    glqr.new("HELLO WORLD")
    |> glqr.error_correction(glqr.H)
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD EC-H printable")
}

pub fn hello_world_v5_printable_test() {
  let assert Ok(matrix) =
    glqr.new("HELLO WORLD") |> glqr.min_version(5) |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD version 5 printable")
}

pub fn numeric_printable_test() {
  let assert Ok(matrix) = glqr.new("1234567890") |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "numeric 1234567890 printable")
}

pub fn utf8_printable_test() {
  let assert Ok(matrix) = glqr.new("Hello, 世界!") |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "UTF-8 Hello World printable")
}

pub fn url_svg_test() {
  let assert Ok(matrix) = glqr.new("https://gleam.run") |> glqr.generate
  matrix
  |> glqr.to_svg
  |> birdie.snap(title: "URL https://gleam.run svg")
}

pub fn hello_world_qr_test() {
  let config = glqr.new("HELLO WORLD")
  let assert Ok(matrix) = glqr.generate(config)
  let expected = [
    [
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
    ],
    [
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
    ],
    [
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
    ],
    [
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
    ],
    [
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
    ],
    [
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Light,
      glqr.Dark,
      glqr.Dark,
      glqr.Dark,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Light,
      glqr.Dark,
    ],
  ]
  assert matrix == expected
}

pub fn empty_value_error_test() {
  glqr.new("")
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.EmptyValue("Provided value cannot be empty"))
}

pub fn version_too_low_error_test() {
  glqr.new("HELLO WORLD")
  |> glqr.min_version(0)
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.InvalidVersion(0))
}

pub fn version_too_high_error_test() {
  glqr.new("HELLO WORLD")
  |> glqr.min_version(41)
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.InvalidVersion(41))
}

pub fn version_negative_error_test() {
  glqr.new("HELLO WORLD")
  |> glqr.min_version(-1)
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.InvalidVersion(-1))
}

pub fn value_exceeds_capacity_error_test() {
  let long_value = string.repeat("A", 4297)
  glqr.new(long_value)
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.ProvidedValueExceedsCapacity(
    value_length: 4297,
    capacity: 4296,
  ))
}
