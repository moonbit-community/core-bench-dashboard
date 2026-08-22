///|
/// The toolchain that ran the benchmarks, one line per component.
pub async fn get_moon_version() -> Array[String] {
  let (code, stdout, stderr) = @process.collect_output("moon", [
    "version", "--all",
  ])
  if code != 0 {
    let message = stderr.text().trim().to_owned()
    let detail = if message.is_empty() { "" } else { ": \{message}" }
    fail("moon version --all failed with exit code \{code}\{detail}")
  }
  let lines = []
  for line in stdout.text().split("\n") {
    let line = line.trim().to_owned()
    if !line.is_empty() {
      lines.push(line)
    }
  }
  lines
}
