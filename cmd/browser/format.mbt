// Turning numbers and timestamps into the strings the table shows.

///|
/// A duration in microseconds, in whichever unit reads best.
fn format_time(us : Double?) -> String {
  guard us is Some(us) else { return "-" }
  if us < 1.0 {
    "\{to_fixed(us * 1000.0, 2)} ns"
  } else if us < 1000.0 {
    "\{to_fixed(us, 2)} us"
  } else if us < 1000000.0 {
    "\{to_fixed(us / 1000.0, 2)} ms"
  } else {
    "\{to_fixed(us / 1000000.0, 2)} s"
  }
}

///|
/// A signed percentage, or nothing at all when there is no comparison.
fn format_delta(delta : Double?) -> String {
  guard delta is Some(delta) else { return "" }
  let sign = if delta > 0.0 { "+" } else { "" }
  "\{sign}\{to_fixed(delta, 1)}%"
}

///|
fn format_generated_at(value : String?) -> String {
  match value {
    None => "-"
    Some(value) => format_local(value)
  }
}

///|
fn short_commit(commit : String?) -> String {
  match commit {
    Some(commit) if commit.length() > 12 => commit[0:12].to_owned()
    Some(commit) => commit
    None => "-"
  }
}

///|
/// The label a row shows for its benchmark.
fn row_label(row : @core_bench.Row) -> String {
  if row.case_name.is_empty() {
    row.block_label
  } else {
    "\{row.block_label} / \{row.case_name}"
  }
}
