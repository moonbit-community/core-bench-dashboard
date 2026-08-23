# Core Benchmark Dashboard

[![Dashboard status](https://moonbit-community.github.io/core-bench-dashboard/data/core-bench/status.svg)](https://moonbit-community.github.io/core-bench-dashboard/)

Core Benchmark Dashboard tracks daily `moon bench` results for the latest `moonbitlang/core` `main` branch on
`darwin-arm64`. Benchmarks run on a self-hosted Apple Silicon runner against the nightly MoonBit toolchain for `wasm`,
`wasm-gc`, `js`, and `native`. CI publishes current JSONL data, keeps 14 retained history days, and marks 5%
day-over-day changes.

The dashboard is written in MoonBit: one native binary collects and publishes, and a
[Rabbita](https://github.com/moonbit-community/rabbita) app renders the site. Both read the same
`core_bench` package, so the browser and the badge can never disagree about what a regression is.

## Build

```sh
moon build --target native --release
cp _build/native/release/build/cmd/dashboard/dashboard.exe dashboard
```

The dashboard is built with the **stable** toolchain even though it benchmarks nightly: see
[Operations](docs/operations.md).

## Collect Data

```sh
./dashboard collect \
  --core-dir ../core \
  --os darwin-arm64 \
  --backends wasm,wasm-gc,js,native \
  --out-dir data/core-bench/current/darwin-arm64
```

The collector writes `data/core-bench/current/darwin-arm64/data.jsonl` and backend logs under
`data/core-bench/current/darwin-arm64/logs/`.

## Publish Assets

```sh
git clone --branch bench-data --single-branch --depth 1 \
  https://github.com/moonbit-community/core-bench-dashboard.git data
./dashboard update-history
./dashboard status-badge
warren build --server-entry ""
```

Retained history lives on the `bench-data` branch, not in the published site. See
[Operations](docs/operations.md).

`warren build` writes `dist/index.html` and `dist/index.js`. Install it once with
`moon install moonbit-community/warren`.

## Development

```sh
moon fmt
moon check --target all
moon test --target all
warren dev --server-entry ""
```

`moon test --target all` runs the shared logic on every backend the dashboard measures; the collector and
history tests are native-only and run under `--target native`.

## Documentation

- [Architecture](docs/architecture.md)
- [Operations](docs/operations.md)
- [Data API](docs/data-api.md)
