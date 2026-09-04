// Folding a day into history, rewriting its log paths, and pruning.

///|
fn history_metadata(date : String) -> @core_bench.Metadata {
  {
    generated_at: "\{date}T00:00:00.000Z",
    run_id: "1",
    run_number: "1",
    os: @core_bench.DASHBOARD_OS,
    backends: [Wasm],
    toolchain_version: ["moon test"],
    core_repo: @core_bench.CORE_REPO,
    core_commit_sha: "a".repeat(40),
  }
}

///|
fn history_record(
  mean : Double,
  stdout_path : String,
  stderr_path : String,
) -> @core_bench.Record {
  {
    benchmark_id: "wasm|pkg|file.mbt|1|bench|",
    backend: Wasm,
    pkg: "moonbitlang/core/pkg",
    file: "pkg/file.mbt",
    line: 1,
    block_label: "bench",
    case_name: "",
    status: Succeeded,
    mean_us: Some(mean),
    stddev_us: None,
    min_us: None,
    max_us: None,
    runs: None,
    batch_size: None,
    stdout_path: Some(stdout_path),
    stderr_path: Some(stderr_path),
    reason: None,
    expanded_command: None,
  }
}

///|
/// Write a current day, the way the collector would have left it.
async fn write_current(data_dir : String, date : String, mean : Double) -> Unit {
  let out_dir = join3(data_dir, "current", @core_bench.DASHBOARD_OS)
  let stdout = join3(out_dir, "logs", "stdout.log")
  let stderr = join3(out_dir, "logs", "stderr.log")
  ensure_dir(join(out_dir, "logs"))
  @fs.write_file(stdout, "stdout \{mean}\n", create_mode=CreateOrTruncate)
  @fs.write_file(stderr, "stderr \{mean}\n", create_mode=CreateOrTruncate)
  write_file(
    join(out_dir, "data.jsonl"),
    @core_bench.stringify_jsonl(history_metadata(date), [
      history_record(mean, stdout, stderr),
    ]),
  )
}

///|
async test "update_history replaces same-day entries, rewrites log paths, and prunes to retention" {
  let root = @fs.tmpdir(prefix="core-bench-history-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let data_dir = join(root, "data/core-bench")
  for day in 1..<=15 {
    let name = "2026-05-\{if day < 10 { "0" } else { "" }}\{day}"
    ensure_dir(join3(data_dir, "history", name))
  }
  write_current(data_dir, "2026-05-24", 10.0)
  let (index, folded) = update_history(data_dir, "2026-05-24", 14)
  assert_true(folded)
  assert_eq(index.days.length(), 14)
  assert_eq(index.days[0].date, "2026-05-03")
  assert_eq(index.days[index.days.length() - 1].date, "2026-05-24")
  let history_dir = join(
    join3(data_dir, "history", "2026-05-24"),
    @core_bench.DASHBOARD_OS,
  )
  let history_path = join(history_dir, "data.jsonl")
  let history = read_jsonl_file(history_path)
  assert_eq(history.records[0].mean_us, Some(10.0))
  assert_eq(
    history.records[0].stdout_path,
    Some(join3(history_dir, "logs", "stdout.log")),
  )
  assert_eq(
    @fs.read_file(history.records[0].stdout_path.unwrap()).text(),
    "stdout 10\n",
  )

  // A second run on the same date replaces the day rather than adding one.
  write_current(data_dir, "2026-05-24", 20.0)
  let (index, _) = update_history(data_dir, "2026-05-24", 14)
  assert_eq(index.days.filter(day => day.date == "2026-05-24").length(), 1)
  let history = read_jsonl_file(history_path)
  assert_eq(history.records[0].mean_us, Some(20.0))
  assert_eq(
    @fs.read_file(history.records[0].stdout_path.unwrap()).text(),
    "stdout 20\n",
  )
}

///|
async test "update_history refuses a date that is not a calendar day" {
  let root = @fs.tmpdir(prefix="core-bench-history-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  try
    update_history(join(root, "data/core-bench"), "2026-5-24", 14) |> ignore
  catch {
    error => assert_true("\{error}".contains("Invalid history date"))
  } noraise {
    _ => fail("expected an invalid date to raise")
  }
}

///|
/// A failure record, the way the collector leaves one when `moon bench` dies.
fn failed_record() -> @core_bench.Record {
  {
    benchmark_id: "wasm|moonbitlang/core||0|moon bench command|",
    backend: Wasm,
    pkg: "moonbitlang/core",
    file: "",
    line: 0,
    block_label: "moon bench command",
    case_name: "",
    status: Failed,
    mean_us: None,
    stddev_us: None,
    min_us: None,
    max_us: None,
    runs: None,
    batch_size: None,
    stdout_path: None,
    stderr_path: None,
    reason: Some("moon bench failed with exit code 1"),
    expanded_command: None,
  }
}

///|
async test "a day that measured nothing is not folded into history" {
  // The whole point: a day of failures must not become the day the next run is
  // compared against, or every benchmark reads `new` the morning after.
  let root = @fs.tmpdir(prefix="core-bench-history-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let data_dir = join(root, "data/core-bench")
  write_current(data_dir, "2026-05-23", 10.0)
  let (_, folded) = update_history(data_dir, "2026-05-23", 14)
  assert_true(folded)
  let out_dir = join3(data_dir, "current", @core_bench.DASHBOARD_OS)
  write_file(
    join(out_dir, "data.jsonl"),
    @core_bench.stringify_jsonl(history_metadata("2026-05-24"), [
      failed_record(),
    ]),
  )
  let (index, folded) = update_history(data_dir, "2026-05-24", 14)
  assert_false(folded)
  // The failed day is absent, and the last good day is still the one to beat.
  assert_eq(index.days.map(day => day.date), ["2026-05-23"])
  let missing = try {
    @fs.kind(join3(data_dir, "history", "2026-05-24")) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(missing)
}

///|
async test "a day with one failed backend is still folded" {
  // Only a day that measured *nothing* is dropped. A partial failure still
  // carries real numbers for the backends that ran.
  let root = @fs.tmpdir(prefix="core-bench-history-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let data_dir = join(root, "data/core-bench")
  let out_dir = join3(data_dir, "current", @core_bench.DASHBOARD_OS)
  let stdout = join3(out_dir, "logs", "stdout.log")
  ensure_dir(join(out_dir, "logs"))
  @fs.write_file(stdout, "stdout\n", create_mode=CreateOrTruncate)
  write_file(
    join(out_dir, "data.jsonl"),
    @core_bench.stringify_jsonl(history_metadata("2026-05-24"), [
      failed_record(),
      history_record(10.0, stdout, stdout),
    ]),
  )
  let (index, folded) = update_history(data_dir, "2026-05-24", 14)
  assert_true(folded)
  assert_eq(index.days.map(day => day.date), ["2026-05-24"])
}
