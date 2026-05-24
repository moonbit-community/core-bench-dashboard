import { assertAlmostEquals, assertEquals } from './assert.ts';
import { normalizeTimeToMicroseconds, parseMoonBenchOutput } from './bench_parser.ts';

Deno.test('normalizeTimeToMicroseconds supports benchmark display units', () => {
  assertAlmostEquals(normalizeTimeToMicroseconds(500, 'ns'), 0.5);
  assertAlmostEquals(normalizeTimeToMicroseconds(12.5, 'µs'), 12.5);
  assertAlmostEquals(normalizeTimeToMicroseconds(12.5, 'μs'), 12.5);
  assertAlmostEquals(normalizeTimeToMicroseconds(12.5, 'us'), 12.5);
  assertAlmostEquals(normalizeTimeToMicroseconds(2.25, 'ms'), 2250);
  assertAlmostEquals(normalizeTimeToMicroseconds(1.5, 's'), 1_500_000);
});

Deno.test('parseMoonBenchOutput parses a single benchmark block from core random', () => {
  const output = `
[moonbitlang/core] bench random/random_test.mbt:108 ("bench random") ok
time (mean ± σ)         range (min … max) 
 184.86 ms ± 581.20 µs   184.19 ms … 186.15 ms  in 10 ×      1 runs
Total tests: 1, passed: 1, failed: 0.
`;

  const records = parseMoonBenchOutput(output, 'wasm');
  assertEquals(records.length, 1);
  assertEquals(records[0].benchmark_id, 'wasm|moonbitlang/core/random|random/random_test.mbt|108|bench random|');
  assertEquals(records[0].package, 'moonbitlang/core/random');
  assertEquals(records[0].case_name, '');
  assertAlmostEquals(records[0].mean_us, 184_860);
  assertAlmostEquals(records[0].stddev_us, 581.2);
  assertAlmostEquals(records[0].min_us, 184_190);
  assertAlmostEquals(records[0].max_us, 186_150);
  assertEquals(records[0].runs, 10);
  assertEquals(records[0].batch_size, 1);
});

Deno.test('parseMoonBenchOutput parses multiple single blocks from core immut/vector', () => {
  const output = `
[moonbitlang/core] bench immut/vector/vector_iter_bench_test.mbt:24 ("bench Vector::iter fold n=100000") ok
time (mean ± σ)         range (min … max) 
   5.62 ms ±  40.12 µs     5.57 ms …   5.69 ms  in 10 ×     18 runs
[moonbitlang/core] bench immut/vector/vector_iter_bench_test.mbt:30 ("bench Vector::iter each n=100000") ok
time (mean ± σ)         range (min … max) 
   5.81 ms ±  34.53 µs     5.76 ms …   5.87 ms  in 10 ×     18 runs
[moonbitlang/core] bench immut/vector/vector_contains_bench_test.mbt:24 ("bench Vector::contains missing n=100000") ok
time (mean ± σ)         range (min … max) 
  76.94 µs ±   3.03 µs    73.93 µs …  81.18 µs  in 10 ×   1227 runs
Total tests: 3, passed: 3, failed: 0.
`;

  const records = parseMoonBenchOutput(output, 'wasm-gc');
  assertEquals(records.map((record) => record.block_label), [
    'bench Vector::iter fold n=100000',
    'bench Vector::iter each n=100000',
    'bench Vector::contains missing n=100000',
  ]);
  assertEquals(records.map((record) => record.package), [
    'moonbitlang/core/immut/vector',
    'moonbitlang/core/immut/vector',
    'moonbitlang/core/immut/vector',
  ]);
  assertAlmostEquals(records[0].mean_us, 5620);
  assertAlmostEquals(records[2].mean_us, 76.94);
});

Deno.test('parseMoonBenchOutput parses named batch benchmark rows from MoonBit docs', () => {
  const output = `
[moonbitlang/core] bench bench/bench_test.mbt:99 ("batch fib") ok
name      time (mean ± σ)         range (min … max) 
naive_fib   21.01 µs ±   0.21 µs    20.76 µs …  21.32 µs  in 10 ×   4632 runs
fast_fib     0.02 µs ±   0.00 µs     0.02 µs …   0.02 µs  in 10 × 100000 runs
Total tests: 1, passed: 1, failed: 0.
`;

  const records = parseMoonBenchOutput(output, 'js');
  assertEquals(records.map((record) => record.case_name), ['naive_fib', 'fast_fib']);
  assertEquals(records[0].benchmark_id, 'js|moonbitlang/core/bench|bench/bench_test.mbt|99|batch fib|naive_fib');
  assertAlmostEquals(records[0].mean_us, 21.01);
  assertAlmostEquals(records[1].mean_us, 0.02);
  assertEquals(records[1].batch_size, 100000);
});
