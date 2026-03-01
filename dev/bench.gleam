//// A small benchmark for QR code generation.
////
//// Run it with:
////
//// ```sh
//// gleam run -m bench
//// ```

import gleam/io
import gleam/string
import gleamy/bench
import glqr

pub fn main() {
  bench.run(
    [
      bench.Input("v1 (11 chars)", glqr.new("HELLO WORLD")),
      bench.Input("v10 (500 chars)", glqr.new(string.repeat("A", 500))),
      bench.Input(
        "v40 (4200 chars)",
        glqr.new(string.repeat("A", 4200)) |> glqr.error_correction(glqr.L),
      ),
    ],
    [bench.Function("glqr.generate", glqr.generate)],
    [bench.Duration(1000), bench.Warmup(200)],
  )
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println()
}
