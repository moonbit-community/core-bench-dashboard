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
