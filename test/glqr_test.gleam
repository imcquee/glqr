import birdie
import gleam/bit_array
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

pub fn hello_world_v5_q_printable_test() {
  let assert Ok(matrix) =
    glqr.new("HELLO WORLD")
    |> glqr.error_correction(glqr.Q)
    |> glqr.min_version(5)
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "HELLO WORLD EC-Q version 5 printable")
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
  let assert Ok(qr) = glqr.generate(config)
  // Convert to bits and verify
  let #(size, bits) = glqr.to_bits(qr)
  // Expected 21x21 QR code (version 1)
  size |> should.equal(21)
  // 21x21 = 441 bits = 55 bytes + 1 bit
  let expected_bit_count = 21 * 21
  let actual_bit_count = bit_array.bit_size(bits)
  actual_bit_count |> should.equal(expected_bit_count)
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
  let long_value = string.repeat("A", 3392)
  glqr.new(long_value)
  |> glqr.generate
  |> should.be_error
  |> should.equal(glqr.ProvidedValueExceedsCapacity(
    value_length: 3392,
    capacity: 3391,
  ))
}

pub fn wifi_wpa_test() {
  glqr.wifi(
    ssid: "MyNetwork",
    authentication: glqr.Wpa("hunter2"),
    hidden: False,
  )
  |> should.equal("WIFI:S:MyNetwork;T:WPA;P:hunter2;;")
}

pub fn wifi_wep_hidden_test() {
  glqr.wifi(
    ssid: "MyNetwork",
    authentication: glqr.Wep("hunter2"),
    hidden: True,
  )
  |> should.equal("WIFI:S:MyNetwork;T:WEP;P:hunter2;H:true;;")
}

pub fn wifi_open_test() {
  glqr.wifi(ssid: "Cafe Guest", authentication: glqr.NoPassword, hidden: False)
  |> should.equal("WIFI:S:Cafe Guest;T:nopass;;")
}

pub fn wifi_escaping_test() {
  glqr.wifi(
    ssid: "Net;work",
    authentication: glqr.Wpa("pa\\ss:word\"quote,comma"),
    hidden: False,
  )
  |> should.equal(
    "WIFI:S:Net\\;work;T:WPA;P:pa\\\\ss\\:word\\\"quote\\,comma;;",
  )
}

pub fn v_card_minimal_test() {
  glqr.v_card(name: "Lucy Gleam")
  |> glqr.v_card_to_string
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Lucy Gleam\r\nFN:Lucy Gleam\r\nEND:VCARD",
  )
}

pub fn v_card_full_test() {
  glqr.v_card(name: "Lucy Gleam")
  |> glqr.v_card_organization("Gleam Industries")
  |> glqr.v_card_job_title("Star")
  |> glqr.v_card_phone("+461234567")
  |> glqr.v_card_email("lucy@gleam.run")
  |> glqr.v_card_address("1 Beam Street, Erlangen")
  |> glqr.v_card_website("https://gleam.run")
  |> glqr.v_card_note("Loves type safety")
  |> glqr.v_card_to_string
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Lucy Gleam\r\nFN:Lucy Gleam\r\n"
    <> "ORG:Gleam Industries\r\nTITLE:Star\r\nTEL:+461234567\r\n"
    <> "EMAIL:lucy@gleam.run\r\nADR:;;1 Beam Street\\, Erlangen;;;;\r\n"
    <> "URL:https://gleam.run\r\nNOTE:Loves type safety\r\nEND:VCARD",
  )
}

pub fn calendar_event_test() {
  glqr.calendar_event(
    summary: "Gleam meetup",
    starts_at: "20260719T093000Z",
    ends_at: "20260719T103000Z",
  )
  |> glqr.calendar_event_location("Stockholm")
  |> glqr.calendar_event_description("Talks; and fika")
  |> glqr.calendar_event_to_string
  |> should.equal(
    "BEGIN:VEVENT\r\nSUMMARY:Gleam meetup\r\nDTSTART:20260719T093000Z\r\n"
    <> "DTEND:20260719T103000Z\r\nLOCATION:Stockholm\r\n"
    <> "DESCRIPTION:Talks\\; and fika\r\nEND:VEVENT",
  )
}

pub fn email_test() {
  glqr.email("hello@example.com")
  |> should.equal("mailto:hello@example.com")
}

pub fn phone_test() {
  glqr.phone("+461234567")
  |> should.equal("tel:+461234567")
}

pub fn sms_test() {
  glqr.sms(number: "+461234567", message: "Hello!")
  |> should.equal("smsto:+461234567:Hello!")
}

pub fn sms_no_message_test() {
  glqr.sms(number: "+461234567", message: "")
  |> should.equal("smsto:+461234567")
}

pub fn geo_test() {
  glqr.geo(latitude: 59.3293, longitude: 18.0686)
  |> should.equal("geo:59.3293,18.0686")
}

pub fn wifi_printable_test() {
  let assert Ok(matrix) =
    glqr.wifi(
      ssid: "MyNetwork",
      authentication: glqr.Wpa("hunter2"),
      hidden: False,
    )
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "WiFi WPA printable")
}

pub fn v_card_printable_test() {
  let assert Ok(matrix) =
    glqr.v_card(name: "Lucy Gleam")
    |> glqr.v_card_phone("+461234567")
    |> glqr.v_card_email("lucy@gleam.run")
    |> glqr.v_card_website("https://gleam.run")
    |> glqr.v_card_to_string
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "vCard printable")
}

pub fn calendar_event_printable_test() {
  let assert Ok(matrix) =
    glqr.calendar_event(
      summary: "Gleam meetup",
      starts_at: "20260719T093000Z",
      ends_at: "20260719T103000Z",
    )
    |> glqr.calendar_event_location("Stockholm")
    |> glqr.calendar_event_to_string
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "calendar event printable")
}

pub fn email_printable_test() {
  let assert Ok(matrix) =
    glqr.email("hello@example.com")
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "email mailto printable")
}

pub fn phone_printable_test() {
  let assert Ok(matrix) =
    glqr.phone("+461234567")
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "phone tel printable")
}

pub fn sms_printable_test() {
  let assert Ok(matrix) =
    glqr.sms(number: "+461234567", message: "Hello!")
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "sms smsto printable")
}

pub fn geo_printable_test() {
  let assert Ok(matrix) =
    glqr.geo(latitude: 59.3293, longitude: 18.0686)
    |> glqr.new
    |> glqr.generate
  matrix
  |> glqr.to_printable
  |> birdie.snap(title: "geo location printable")
}
