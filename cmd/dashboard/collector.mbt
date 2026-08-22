// Running `moon bench` once per backend against a checked-out core tree.

///|
const DEFAULT_BENCH_TIMEOUT_SECONDS : Int = 3600

///|
pub(all) struct CollectOptions {
  core_dir : String
  os : String
  backends : Array[@core_bench.Backend]
  out_dir : String
  bench_timeout_seconds : Int
}

///|
/// How one `moon bench` invocation ended.
priv struct ProcessResult {
  success : Bool
  code : Int
  reason : String?
}

///|
/// Where one backend's two logs are written.
priv struct LogPaths {
  stdout : String
  stderr : String
}

///|
async fn run_git(args : Array[String], cwd : String) -> String {
  let (code, stdout, stderr) = @process.collect_output("git", args, cwd~)
  if code != 0 {
    let message = stderr.text().trim().to_owned()
    let detail = if message.is_empty() { "" } else { ": \{message}" }
    fail("git \{args.join(" ")} failed with exit code \{code}\{detail}")
  }
  stdout.text().trim().to_owned()
}

///|
/// The commit the benchmarks were taken against.
async fn read_core_commit(core_dir : String) -> String {
  let is_directory = try (@fs.kind(core_dir) is Directory) catch {
    _ => false
  }
  if !is_directory {
    fail("--core-dir does not exist or is not a directory: \{core_dir}")
  }
  run_git(["rev-parse", "HEAD"], core_dir)
}

///|
/// The toolchain that produced the numbers, or why it could not be read.
async fn read_toolchain_version() -> Array[String] {
  get_moon_version() catch {
    error => ["unavailable: \{error}"]
  }
}

///|
/// Log file names are stable per platform and backend, so a day's logs
/// overwrite the previous day's rather than accumulating.
async fn log_paths(
  out_dir : String,
  os : String,
  backend : @core_bench.Backend,
) -> LogPaths {
  ensure_dir(join(out_dir, "logs"))
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode("core|\{os}|\{backend}")),
  )
  let prefix = digest[0:16].to_owned()
  {
    stdout: join3(out_dir, "logs", "\{prefix}.\{backend}.stdout.log"),
    stderr: join3(out_dir, "logs", "\{prefix}.\{backend}.stderr.log"),
  }
}

///|
fn command_for_backend(
  backend : @core_bench.Backend,
  target_dir : String,
) -> Array[String] {
  [
    "moon",
    "bench",
    "--target",
    backend.name(),
    "--target-dir",
    target_dir,
    "--frozen",
    "--no-parallelize",
  ]
}

///|
/// Run one benchmark command, streaming both streams straight to their logs.
async fn run_bench_command(
  args : Array[String],
  cwd : String,
  timeout_seconds : Int,
  paths : LogPaths,
) -> ProcessResult {
  try {
    let stdout = @process.redirect_to_file(
      paths.stdout,
      create_mode=CreateOrTruncate,
    )
    let stderr = @process.redirect_to_file(
      paths.stderr,
      create_mode=CreateOrTruncate,
    )
    let exit_code = @async.with_timeout_opt(timeout_seconds * 1000, () => {
      @process.run(args[0], args[1:], cwd~, stdout~, stderr~)
    })
    match exit_code {
      Some(code) => { success: code == 0, code, reason: None }
      None =>
        {
          success: false,
          code: 124,
          reason: Some("Command timed out after \{timeout_seconds} seconds."),
        }
    }
  } catch {
    error => {
      // The command never started, so its stderr log is the only place left to
      // say why.
      let message = "\{error}"
      @fs.write_file(paths.stderr, message, create_mode=CreateOrTruncate) catch {
        _ => ()
      }
      { success: false, code: 1, reason: Some(message) }
    }
  }
}

///|
/// A backend whose benchmark command produced nothing usable.
fn command_error_record(
  backend : @core_bench.Backend,
  paths : LogPaths,
  expanded_command : Array[String],
  reason : String,
) -> @core_bench.Record {
  {
    benchmark_id: "\{backend}|moon bench command",
    backend,
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
    stdout_path: Some(paths.stdout),
    stderr_path: Some(paths.stderr),
    reason: Some(reason),
    expanded_command: Some(expanded_command),
  }
}

///|
/// Collect one backend, always returning at least one record.
async fn collect_backend(
  options : CollectOptions,
  backend : @core_bench.Backend,
  temp_root : String,
) -> Array[@core_bench.Record] {
  let paths = log_paths(options.out_dir, options.os, backend)
  let target_dir = join3(temp_root, backend.name(), "build")
  ensure_dir(target_dir)
  let command = command_for_backend(backend, target_dir)
  let result = run_bench_command(
    command,
    options.core_dir,
    options.bench_timeout_seconds,
    paths,
  )
  if !result.success {
    let stderr = @fs.read_file(paths.stderr).text().trim().to_owned() catch {
        _ => ""
      }
    let reason = match result.reason {
      Some(reason) => reason
      None if stderr.is_empty() =>
        "moon bench failed with exit code \{result.code}"
      None =>
        "moon bench failed with exit code \{result.code}: \{head(stderr, 500)}"
    }
    return [command_error_record(backend, paths, command, reason)]
  }
  let stdout = @fs.read_file(paths.stdout).text()
  let records = @bench_parser.parse_moon_bench_output(stdout, backend).map(record => {
    ..record,
    stdout_path: Some(paths.stdout),
    stderr_path: Some(paths.stderr),
    expanded_command: Some(command),
  })
  if records.is_empty() {
    return [
      command_error_record(
        backend, paths, command, "moon bench produced no parsed records.",
      ),
    ]
  }
  records
}

///|
/// Collect every requested backend and describe the run that produced them.
pub async fn collect_core_bench(
  options : CollectOptions,
) -> (@core_bench.Metadata, Array[@core_bench.Record]) {
  let core_commit_sha = read_core_commit(options.core_dir)
  let temp_root = @fs.tmpdir(prefix="core-bench-")
  let records = []
  defer (@fs.rmdir(temp_root, recursive=true) catch { _ => () })
  for backend in options.backends {
    for record in collect_backend(options, backend, temp_root) {
      records.push(record)
    }
  }
  let metadata : @core_bench.Metadata = {
    generated_at: iso_now(),
    run_id: env_or("GITHUB_ACTION_RUN_ID", "0"),
    run_number: env_or("GITHUB_ACTION_RUN_NUMBER", "0"),
    os: options.os,
    backends: options.backends.copy(),
    toolchain_version: read_toolchain_version(),
    core_repo: @core_bench.CORE_REPO,
    core_commit_sha,
  }
  (metadata, records)
}
