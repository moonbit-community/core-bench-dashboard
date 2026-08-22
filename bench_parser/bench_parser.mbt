// Parser for rendered `moon bench` output.
//
// The two patterns below are the whole grammar. They are spelled out in full
// rather than assembled from pieces because a regex literal is checked at
// compile time, and a pattern built by concatenation is not.
//
//   NUMBER  [\-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][\-+]?[0-9]+)?
//   UNIT    ns|us|ms|s|min, with both micro signs accepted
//
// `moon bench` writes the micro sign as either U+00B5 or U+03BC depending on
// the platform's rendering, so both are matched and both normalize the same.

///|
/// An escape sequence introduced by a terminal, to be removed before parsing.
const ANSI : Regex = re"\u{1b}\[[0-?]*[ -/]*[@-~]"

///|
/// `[module] bench file:line ("label") result`
const HEADER : Regex = re"^\[(?<module>[^\]]+)\][[:space:]]+bench[[:space:]]+(?<file>.*?):(?<line>[0-9]+)[[:space:]]+\(\"(?<label>(?:\\.|[^\"])*)\"\)[[:space:]]+(?<result>[^[:space:]]+)"

///|
/// `mean ± stddev  min … max  in runs × batch_size runs`
const TIMING : Regex = re"(?<mean>[\-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][\-+]?[0-9]+)?)[[:space:]]*(?<meanUnit>ns|µs|μs|us|ms|s|min)[[:space:]]*±[[:space:]]*(?<stddev>[\-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][\-+]?[0-9]+)?)[[:space:]]*(?<stddevUnit>ns|µs|μs|us|ms|s|min)[[:space:]]+(?<min>[\-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][\-+]?[0-9]+)?)[[:space:]]*(?<minUnit>ns|µs|μs|us|ms|s|min)[[:space:]]*(?:…|\.\.\.)[[:space:]]*(?<max>[\-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][\-+]?[0-9]+)?)[[:space:]]*(?<maxUnit>ns|µs|μs|us|ms|s|min)[[:space:]]+in[[:space:]]+(?<runs>[0-9]+)[[:space:]]*×[[:space:]]*(?<batchSize>[0-9]+)[[:space:]]+runs"

///|
/// A benchmark time carried a unit the dashboard cannot normalize.
pub(all) suberror UnsupportedTimeUnit {
  UnsupportedTimeUnit(String)
}

///|
pub impl Show for UnsupportedTimeUnit with fn output(self, logger) {
  let UnsupportedTimeUnit(unit) = self
  logger.write_string("Unsupported benchmark time unit: \{unit}")
}

///|
/// The header line that every following timing row belongs to.
priv struct BenchContext {
  module_name : String
  file : String
  line : Int
  label : String
}

///|
/// One timing row, with the column where its numbers begin.
priv struct Timing {
  offset : Int
  mean_us : Double
  stddev_us : Double
  min_us : Double
  max_us : Double
  runs : Int
  batch_size : Int
}

///|
/// Remove terminal escape sequences.
pub fn strip_ansi(value : String) -> String {
  ANSI.replace_by(value, _ => "").to_owned()
}

///|
/// Convert a benchmark time to microseconds.
pub fn normalize_time_to_microseconds(
  value : Double,
  unit : String,
) -> Double raise UnsupportedTimeUnit {
  match unit {
    "ns" => value / 1000.0
    "µs" | "μs" | "us" => value
    "ms" => value * 1000.0
    "s" => value * 1000000.0
    "min" => value * 60000000.0
    _ => raise UnsupportedTimeUnit(unit)
  }
}

///|
fn unescape_label(value : String) -> String {
  value.replace_all(old="\\\"", new="\"").replace_all(old="\\\\", new="\\")
}

///|
/// The package a benchmark belongs to, from its module and file path.
fn package_from_file(module_name : String, file : String) -> String {
  let normalized = file.replace_all(old="\\", new="/")
  match normalized.rev_split_once("/") {
    Some((dir, _)) => "\{module_name}/\{dir}"
    None => module_name
  }
}

///|
fn benchmark_id(
  backend : @core_bench.Backend,
  identity : @core_bench.Identity,
) -> String {
  [
    backend.name(),
    identity.pkg,
    identity.file,
    identity.line.to_string(),
    identity.block_label,
    identity.case_name,
  ].join("|")
}

///|
fn parse_header(line : String) -> BenchContext? {
  guard HEADER.execute(line) is Some(m) else { return None }
  guard m.named_group("module") is Some(module_name) else { return None }
  guard m.named_group("file") is Some(file) else { return None }
  guard m.named_group("line") is Some(line_number) else { return None }
  guard m.named_group("label") is Some(label) else { return None }
  let line_value = @string.parse_int(line_number) catch { _ => return None }
  Some({
    module_name: module_name.to_owned(),
    file: file.to_owned(),
    line: line_value,
    label: unescape_label(label.to_owned()),
  })
}

///|
fn number(m : @string.MatchResult, name : String) -> Double? {
  guard m.named_group(name) is Some(view) else { return None }
  Some(@string.parse_double(view) catch { _ => return None })
}

///|
fn integer(m : @string.MatchResult, name : String) -> Int? {
  guard m.named_group(name) is Some(view) else { return None }
  Some(@string.parse_int(view) catch { _ => return None })
}

///|
fn scaled(
  m : @string.MatchResult,
  value_group : String,
  unit_group : String,
) -> Double? raise UnsupportedTimeUnit {
  guard number(m, value_group) is Some(value) else { return None }
  guard m.named_group(unit_group) is Some(unit) else { return None }
  Some(normalize_time_to_microseconds(value, unit.to_owned()))
}

///|
fn parse_timing_line(line : String) -> Timing? raise UnsupportedTimeUnit {
  guard TIMING.execute(line) is Some(m) else { return None }
  guard scaled(m, "mean", "meanUnit") is Some(mean_us) else { return None }
  guard scaled(m, "stddev", "stddevUnit") is Some(stddev_us) else {
    return None
  }
  guard scaled(m, "min", "minUnit") is Some(min_us) else { return None }
  guard scaled(m, "max", "maxUnit") is Some(max_us) else { return None }
  guard integer(m, "runs") is Some(runs) else { return None }
  guard integer(m, "batchSize") is Some(batch_size) else { return None }
  Some({
    offset: m.before().length(),
    mean_us,
    stddev_us,
    min_us,
    max_us,
    runs,
    batch_size,
  })
}

///|
fn record_from_timing(
  backend : @core_bench.Backend,
  context : BenchContext,
  case_name : String,
  timing : Timing,
) -> @core_bench.Record {
  let identity : @core_bench.Identity = {
    pkg: package_from_file(context.module_name, context.file),
    file: context.file,
    line: context.line,
    block_label: context.label,
    case_name,
  }
  {
    benchmark_id: benchmark_id(backend, identity),
    backend,
    pkg: identity.pkg,
    file: identity.file,
    line: identity.line,
    block_label: identity.block_label,
    case_name: identity.case_name,
    status: Succeeded,
    mean_us: Some(timing.mean_us),
    stddev_us: Some(timing.stddev_us),
    min_us: Some(timing.min_us),
    max_us: Some(timing.max_us),
    runs: Some(timing.runs),
    batch_size: Some(timing.batch_size),
    stdout_path: None,
    stderr_path: None,
    reason: None,
    expanded_command: None,
  }
}

///|
/// Parse every benchmark record out of one backend's `moon bench` stdout.
///
/// A block header opens a context; the timing table that follows it produces
/// one record per timing row. A batch table is recognised by its `name` column,
/// and the text left of the numbers becomes the case name.
pub fn parse_moon_bench_output(
  stdout : String,
  backend : @core_bench.Backend,
) -> Array[@core_bench.Record] raise UnsupportedTimeUnit {
  let records = []
  let mut context : BenchContext? = None
  let mut in_time_table = false
  let mut batch_table = false
  for line in strip_ansi(stdout).split("\n") {
    let line = line.trim_end(chars="\r").to_owned()
    if parse_header(line) is Some(header) {
      context = Some(header)
      in_time_table = false
      batch_table = false
      continue
    }
    guard context is Some(current_context) else { continue }
    if line.contains("time (mean") && line.contains("range") {
      in_time_table = true
      batch_table = line.trim_start().has_prefix("name")
      continue
    }
    if !in_time_table {
      continue
    }
    if line.is_blank() || line.has_prefix("Total tests:") {
      in_time_table = false
      continue
    }
    guard parse_timing_line(line) is Some(timing) else { continue }
    let case_name = if batch_table {
      line[0:timing.offset].trim().to_owned()
    } else {
      ""
    }
    records.push(
      record_from_timing(backend, current_context, case_name, timing),
    )
  }
  records
}
