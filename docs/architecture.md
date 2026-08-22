# Architecture

The dashboard is a static MoonBit site with a native companion binary. One module holds four packages:

```text
core_bench/     types, JSONL, row building, badge rendering   every backend
bench_parser/   the `moon bench` output parser                every backend
cmd/dashboard/  collect, restore-history, update-history, status-badge   native
cmd/browser/    the Rabbita dashboard                         js
```

`core_bench` has no I/O. It is the only place that decides what a regression is, and both the browser and the
badge read it, so the site and the badge cannot disagree. `bench_parser` is separate because only the collector
parses benchmark output.

`dashboard collect` runs `moon bench` once per backend against a checked-out `moonbitlang/core` tree. It captures
one stdout and stderr log per backend, parses rendered benchmark tables, and writes newline-delimited JSON where
the first line is metadata and subsequent lines are benchmark records.

Benchmark identity is:

```text
backend + package + file + line + block_label + case_name
```

Single benchmark blocks use an empty `case_name`. Batch benchmark blocks produce one record per named timing row.

Published data lives under:

```text
data/core-bench/current/darwin-arm64/data.jsonl
data/core-bench/history/index.json
data/core-bench/history/<YYYY-MM-DD>/darwin-arm64/data.jsonl
data/core-bench/status.svg
```

The frontend loads current data and retained history directly from those static paths. It compares current records
with the immediately previous retained calendar day using `mean_us`.

## Serialization

Record and metadata types are serialized with [`Yu-zh/data`](https://github.com/Yu-zh/data). Three of its
properties matter here:

- `#data.rename` keeps the published camelCase metadata field names next to snake_case MoonBit fields.
- Unknown fields are skipped rather than rejected, so a schema change does not break the fourteen days of
  already-published history the next run restores.
- An absent field and an explicit `null` both read back as `None`.

Implementations are generated, not written. After changing a type in `core_bench/types.mbt`, re-run:

```sh
moonx Yu-zh/data/derive core_bench
```

and commit the regenerated `core_bench/types_derive.mbt`.

## Ordering

`String::compare` in MoonBit orders by length before content. Every ordering the dashboard shows — history dates,
package and file names, benchmark labels — uses `String::lexical_compare` instead, so rows sort the way a reader
expects to read them.
