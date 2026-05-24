# Architecture

The dashboard is a static Deno/TypeScript site.

`main.ts collect` runs `moon bench` once per backend against a checked-out `moonbitlang/core` tree. It captures one
stdout and stderr log per backend, parses rendered benchmark tables, and writes newline-delimited JSON where the first
line is metadata and subsequent lines are benchmark records.

Benchmark identity is:

```text
backend + package + file + line + block_label + case_name
```

Single benchmark blocks use an empty `case_name`. Batch benchmark blocks produce one record per named timing row.

Published data lives under:

```text
data/core-bench/current/linux-x64/data.jsonl
data/core-bench/history/index.json
data/core-bench/history/<YYYY-MM-DD>/linux-x64/data.jsonl
data/core-bench/status.svg
```

The frontend loads current data and retained history directly from those static paths. It compares current records with
the immediately previous retained calendar day using `mean_us`.
