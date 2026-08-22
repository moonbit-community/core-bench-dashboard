# Data API

`data/core-bench/current/darwin-arm64/data.jsonl` starts with metadata:

```json
{
  "generated_at": "2026-05-24T00:00:00.000Z",
  "runId": "0",
  "runNumber": "0",
  "os": "darwin-arm64",
  "backends": ["wasm", "wasm-gc", "js", "native"],
  "toolchainVersion": [],
  "coreRepo": "https://github.com/moonbitlang/core",
  "coreCommitSha": "..."
}
```

Each following line is one benchmark record with identity fields, normalized timing fields in microseconds, log paths,
and the expanded `moon bench` command.

A field with no value is written as `null` rather than omitted. Readers must treat an absent field and an explicit
`null` alike; `core_bench/jsonl_test.mbt` pins both the field names above and that behaviour.
