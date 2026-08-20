# Core Benchmark Dashboard

[![Dashboard status](https://moonbit-community.github.io/core-bench-dashboard/data/core-bench/status.svg)](https://moonbit-community.github.io/core-bench-dashboard/)

Core Benchmark Dashboard tracks daily `moon bench` results for the latest `moonbitlang/core` `main` branch on
`darwin-arm64`. Benchmarks run on a self-hosted Apple Silicon runner against the nightly MoonBit toolchain for `wasm`,
`wasm-gc`, `js`, and `native`. CI publishes current JSONL data, keeps 14 retained history days, and marks 5%
day-over-day changes.

## Collect Data

```sh
deno run -A main.ts collect \
  --core-dir ../core \
  --os darwin-arm64 \
  --backends wasm,wasm-gc,js,native \
  --out-dir data/core-bench/current/darwin-arm64
```

The collector writes `data/core-bench/current/darwin-arm64/data.jsonl` and backend logs under
`data/core-bench/current/darwin-arm64/logs/`.

## Publish Assets

```sh
deno run -A scripts/restore_history.ts https://moonbit-community.github.io/core-bench-dashboard
deno task update-history
deno task status-badge
deno task bundle
```

## Development

```sh
deno task fmt
deno task lint
deno task check
deno task test
deno task bundle
```

## Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/operations.md)
