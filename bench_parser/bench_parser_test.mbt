///|
fn close_to(actual : Double?, expected : Double) -> Bool {
  match actual {
    Some(value) => (value - expected).abs() <= 1.0e-9
    None => false
  }
}

///|
test "normalize_time_to_microseconds supports benchmark display units" {
  let normalize = @bench_parser.normalize_time_to_microseconds
  assert_eq(normalize(500.0, "ns"), 0.5)
  assert_eq(normalize(12.5, "µs"), 12.5)
  assert_eq(normalize(12.5, "μs"), 12.5)
  assert_eq(normalize(12.5, "us"), 12.5)
  assert_eq(normalize(2.25, "ms"), 2250.0)
  assert_eq(normalize(1.5, "s"), 1500000.0)
  assert_eq(normalize(2.0, "min"), 120000000.0)
}

///|
test "normalize_time_to_microseconds rejects an unknown unit" {
  try @bench_parser.normalize_time_to_microseconds(1.0, "fortnight") catch {
    e => inspect(e, content="Unsupported benchmark time unit: fortnight")
  } noraise {
    _ => fail("expected an unsupported unit to raise")
  }
}

///|
test "strip_ansi removes terminal escapes" {
  assert_eq(@bench_parser.strip_ansi("\u{1b}[32mok\u{1b}[0m plain"), "ok plain")
}

///|
test "parse_moon_bench_output parses a single benchmark block from core random" {
  let output =
    #|
    #|[moonbitlang/core] bench random/random_test.mbt:108 ("bench random") ok
    #|time (mean ± σ)         range (min … max) 
    #| 184.86 ms ± 581.20 µs   184.19 ms … 186.15 ms  in 10 ×      1 runs
    #|Total tests: 1, passed: 1, failed: 0.
    #|
  let records = @bench_parser.parse_moon_bench_output(output, Wasm)
  assert_eq(records.length(), 1)
  assert_eq(
    records[0].benchmark_id,
    "wasm|moonbitlang/core/random|random/random_test.mbt|108|bench random|",
  )
  assert_eq(records[0].pkg, "moonbitlang/core/random")
  assert_eq(records[0].case_name, "")
  assert_eq(records[0].status, Succeeded)
  assert_true(close_to(records[0].mean_us, 184860.0))
  assert_true(close_to(records[0].stddev_us, 581.2))
  assert_true(close_to(records[0].min_us, 184190.0))
  assert_true(close_to(records[0].max_us, 186150.0))
  assert_eq(records[0].runs, Some(10))
  assert_eq(records[0].batch_size, Some(1))
}

///|
test "parse_moon_bench_output parses multiple single blocks from core immut/vector" {
  let output =
    #|
    #|[moonbitlang/core] bench immut/vector/vector_iter_bench_test.mbt:24 ("bench Vector::iter fold n=100000") ok
    #|time (mean ± σ)         range (min … max) 
    #|   5.62 ms ±  40.12 µs     5.57 ms …   5.69 ms  in 10 ×     18 runs
    #|[moonbitlang/core] bench immut/vector/vector_iter_bench_test.mbt:30 ("bench Vector::iter each n=100000") ok
    #|time (mean ± σ)         range (min … max) 
    #|   5.81 ms ±  34.53 µs     5.76 ms …   5.87 ms  in 10 ×     18 runs
    #|[moonbitlang/core] bench immut/vector/vector_contains_bench_test.mbt:24 ("bench Vector::contains missing n=100000") ok
    #|time (mean ± σ)         range (min … max) 
    #|  76.94 µs ±   3.03 µs    73.93 µs …  81.18 µs  in 10 ×   1227 runs
    #|Total tests: 3, passed: 3, failed: 0.
    #|
  let records = @bench_parser.parse_moon_bench_output(output, WasmGc)
  assert_eq(records.map(record => record.block_label), [
    "bench Vector::iter fold n=100000", "bench Vector::iter each n=100000", "bench Vector::contains missing n=100000",
  ])
  assert_eq(records.map(record => record.pkg), [
    "moonbitlang/core/immut/vector", "moonbitlang/core/immut/vector", "moonbitlang/core/immut/vector",
  ])
  assert_true(close_to(records[0].mean_us, 5620.0))
  assert_true(close_to(records[2].mean_us, 76.94))
}

///|
test "parse_moon_bench_output parses named batch benchmark rows" {
  let output =
    #|
    #|[moonbitlang/core] bench bench/bench_test.mbt:99 ("batch fib") ok
    #|name      time (mean ± σ)         range (min … max) 
    #|naive_fib   21.01 µs ±   0.21 µs    20.76 µs …  21.32 µs  in 10 ×   4632 runs
    #|fast_fib     0.02 µs ±   0.00 µs     0.02 µs …   0.02 µs  in 10 × 100000 runs
    #|Total tests: 1, passed: 1, failed: 0.
    #|
  let records = @bench_parser.parse_moon_bench_output(output, Js)
  assert_eq(records.map(record => record.case_name), ["naive_fib", "fast_fib"])
  assert_eq(
    records[0].benchmark_id,
    "js|moonbitlang/core/bench|bench/bench_test.mbt|99|batch fib|naive_fib",
  )
  assert_true(close_to(records[0].mean_us, 21.01))
  assert_true(close_to(records[1].mean_us, 0.02))
  assert_eq(records[1].batch_size, Some(100000))
}

///|
test "a benchmark at the module root keeps the bare module name" {
  let output =
    #|[moonbitlang/core] bench bench_test.mbt:1 ("root") ok
    #|time (mean ± σ)         range (min … max) 
    #|   1.00 us ±   0.10 us     0.90 us …   1.10 us  in 10 ×      1 runs
    #|
  let records = @bench_parser.parse_moon_bench_output(output, Native)
  assert_eq(records[0].pkg, "moonbitlang/core")
}

///|
test "an escaped quote in a block label survives" {
  let output =
    #|[moonbitlang/core] bench a/a_test.mbt:7 ("bench \"quoted\"") ok
    #|time (mean ± σ)         range (min … max) 
    #|   1.00 us ±   0.10 us     0.90 us …   1.10 us  in 10 ×      1 runs
    #|
  let records = @bench_parser.parse_moon_bench_output(output, Native)
  assert_eq(records[0].block_label, "bench \"quoted\"")
}
