// The published data contract, pinned.
//
// These snapshots are the wire shape that `data/core-bench/**/data.jsonl`
// already contains and that fourteen days of retained history are read back
// with. A diff here is a change to published data, not a test detail.

///|
fn sample_metadata() -> @core_bench.Metadata {
  {
    generated_at: "2026-05-24T00:00:00.000Z",
    run_id: "0",
    run_number: "0",
    os: @core_bench.DASHBOARD_OS,
    backends: @core_bench.backends(),
    toolchain_version: ["moon 0.1.0", "moonc v0.1.0"],
    core_repo: @core_bench.CORE_REPO,
    core_commit_sha: "a".repeat(40),
  }
}

///|
fn sample_record() -> @core_bench.Record {
  {
    benchmark_id: "wasm|moonbitlang/core/random|random/random_test.mbt|108|bench random|",
    backend: Wasm,
    pkg: "moonbitlang/core/random",
    file: "random/random_test.mbt",
    line: 108,
    block_label: "bench random",
    case_name: "",
    status: Succeeded,
    mean_us: Some(184860.0),
    stddev_us: Some(581.2),
    min_us: Some(184190.0),
    max_us: Some(186150.0),
    runs: Some(10),
    batch_size: Some(1),
    stdout_path: Some("logs/abc.wasm.stdout.log"),
    stderr_path: Some("logs/abc.wasm.stderr.log"),
    reason: None,
    expanded_command: Some(["moon", "bench", "--target", "wasm"]),
  }
}

///|
test "metadata keeps its published field names" {
  inspect(
    @json.to_string(sample_metadata()),
    content=(
      #|{"generated_at":"2026-05-24T00:00:00.000Z","runId":"0","runNumber":"0","os":"darwin-arm64","backends":["wasm","wasm-gc","js","native"],"toolchainVersion":["moon 0.1.0","moonc v0.1.0"],"coreRepo":"https://github.com/moonbitlang/core","coreCommitSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
    ),
  )
}

///|
test "a record keeps its published field names" {
  inspect(
    @json.to_string(sample_record()),
    content=(
      #|{"benchmark_id":"wasm|moonbitlang/core/random|random/random_test.mbt|108|bench random|","backend":"wasm","package":"moonbitlang/core/random","file":"random/random_test.mbt","line":108,"block_label":"bench random","case_name":"","status":"ok","mean_us":184860,"stddev_us":581.2,"min_us":184190,"max_us":186150,"runs":10,"batch_size":1,"stdout_path":"logs/abc.wasm.stdout.log","stderr_path":"logs/abc.wasm.stderr.log","reason":null,"expanded_command":["moon","bench","--target","wasm"]}
    ),
  )
}

///|
test "a jsonl document round-trips" {
  let text = @core_bench.stringify_jsonl(sample_metadata(), [sample_record()])
  let parsed = @core_bench.parse_jsonl(text)
  assert_eq(parsed.metadata, Some(sample_metadata()))
  assert_eq(parsed.records, [sample_record()])
}

///|
test "history written before an optional field existed still reads" {
  // Published history predates nothing today, but the reader must keep working
  // when a field is added: absent and explicitly null both read back as None,
  // and unknown fields are skipped rather than rejected.
  let line =
    #|{"benchmark_id":"wasm|p|f.mbt|1|b|","backend":"wasm","package":"p","file":"f.mbt","line":1,"block_label":"b","case_name":"","status":"error","reason":"boom","future_field":42}
  let parsed = @core_bench.parse_jsonl(
    "\{@json.to_string(sample_metadata())}\n\{line}\n",
  )
  let record = parsed.records[0]
  assert_eq(record.status, Failed)
  assert_eq(record.mean_us, None)
  assert_eq(record.reason, Some("boom"))
}

///|
test "an empty document is empty rather than an error" {
  assert_eq(@core_bench.parse_jsonl("").records.length(), 0)
  assert_eq(@core_bench.parse_jsonl("\n\n").metadata, None)
}
