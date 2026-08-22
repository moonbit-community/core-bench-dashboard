// The collector, exercised against a fake `moon` on PATH.
//
// Nothing here runs a real benchmark: the point is that the collector spawns
// the command it says it will, captures both streams, and turns the rendered
// output into records.

///|
const FAKE_MOON : String =
  #|#!/usr/bin/env sh
  #|if [ "$1" = "version" ]; then
  #|  echo "moon test"
  #|  exit 0
  #|fi
  #|echo "stderr line" >&2
  #|cat <<'EOF'
  #|[moonbitlang/core] bench random/random_test.mbt:108 ("bench random") ok
  #|time (mean ± σ)         range (min … max)
  #|   1.25 µs ±   0.25 µs     1.00 µs …   1.50 µs  in 10 ×    800 runs
  #|Total tests: 1, passed: 1, failed: 0.
  #|EOF
  #|

///|
const FAILING_MOON : String =
  #|#!/usr/bin/env sh
  #|if [ "$1" = "version" ]; then
  #|  echo "moon test"
  #|  exit 0
  #|fi
  #|echo "boom" >&2
  #|exit 3
  #|

///|
async fn run(command : String, args : Array[String], cwd : String) -> Unit {
  let (code, _, stderr) = @process.collect_output(command, args, cwd~)
  if code != 0 {
    fail("\{command} \{args.join(" ")} failed: \{stderr.text()}")
  }
}

///|
async fn init_git_repo(path : String) -> Unit {
  @fs.mkdir(path, recursive=true)
  run("git", ["init"], path)
  run("git", ["config", "user.email", "test@example.com"], path)
  run("git", ["config", "user.name", "Test User"], path)
  @fs.write_file(
    join(path, "README.md"),
    "# test\n",
    create_mode=CreateOrTruncate,
  )
  run("git", ["add", "README.md"], path)
  run("git", ["commit", "-m", "initial"], path)
}

///|
/// Install a fake `moon` first on PATH and hand back the previous value.
async fn install_fake_moon(bin_dir : String, script : String) -> Unit {
  @fs.mkdir(bin_dir, recursive=true)
  let fake_moon = join(bin_dir, "moon")
  @fs.write_file(fake_moon, script, create_mode=CreateOrTruncate)
  @fs.chmod(fake_moon, 0o755)
}

///|
async fn with_fake_moon(
  script : String,
  body : async (String, String) -> Unit,
) -> Unit {
  let root = @fs.tmpdir(prefix="core-bench-test-")
  let old_path = @env.get_env_var("PATH").unwrap_or("")
  defer {
    @env.set_env_var("PATH", old_path)
    @fs.rmdir(root, recursive=true) catch {
      _ => ()
    }
  }
  let core_dir = join(root, "core")
  let bin_dir = join(root, "bin")
  init_git_repo(core_dir)
  install_fake_moon(bin_dir, script)
  @env.set_env_var("PATH", "\{bin_dir}:\{old_path}")
  body(core_dir, join(root, "out"))
}

///|
/// Both cases live in one test because they take turns owning `PATH`, which is
/// process-global: run as separate tests they can interleave and each would
/// then find the other's fake `moon`.
async test "collect_core_bench captures a good run and explains a bad one" {
  with_fake_moon(FAKE_MOON, (core_dir, out_dir) => {
    let (metadata, records) = collect_core_bench({
      core_dir,
      os: @core_bench.DASHBOARD_OS,
      backends: [Wasm],
      out_dir,
      bench_timeout_seconds: 10,
    })
    assert_eq(metadata.toolchain_version, ["moon test"])
    assert_eq(metadata.core_commit_sha.length(), 40)
    assert_eq(metadata.os, @core_bench.DASHBOARD_OS)
    assert_eq(records.length(), 1)
    assert_eq(records[0].mean_us, Some(1.25))
    assert_eq(records[0].status, Succeeded)
    assert_true(
      records[0].expanded_command
      .unwrap()
      .join(" ")
      .contains("moon bench --target wasm"),
    )
    let stderr = @fs.read_file(records[0].stderr_path.unwrap()).text()
    assert_true(stderr.contains("stderr line"))
  })
  with_fake_moon(FAILING_MOON, (core_dir, out_dir) => {
    let (_, records) = collect_core_bench({
      core_dir,
      os: @core_bench.DASHBOARD_OS,
      backends: [Wasm],
      out_dir,
      bench_timeout_seconds: 10,
    })
    assert_eq(records.length(), 1)
    assert_eq(records[0].status, Failed)
    assert_eq(records[0].block_label, "moon bench command")
    assert_true(records[0].reason.unwrap().contains("exit code 3"))
    assert_true(records[0].reason.unwrap().contains("boom"))
  })
}
