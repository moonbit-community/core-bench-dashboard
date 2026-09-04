// The dashboard's command line: one binary, five commands.
//
// `collect` runs on the benchmark machine. `note` is run by a person, on a
// checkout, when they have concluded something about a regression. The rest run
// wherever the site is published, and only ever touch files and published URLs.

///|
fn option_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some(values) if !values.is_empty() => Some(values[0])
    _ => None
  }
}

///|
fn option_or(
  matches : @argparse.Matches,
  name : String,
  fallback : String,
) -> String {
  option_value(matches, name).unwrap_or(fallback)
}

///|
fn option_int(
  matches : @argparse.Matches,
  name : String,
  fallback : Int,
) -> Int raise {
  match option_value(matches, name) {
    Some(value) => @string.parse_int(value)
    None => fallback
  }
}

///|
/// The dashboard publishes exactly one platform.
fn parse_os(value : String?) -> String raise {
  match value {
    None => @core_bench.DASHBOARD_OS
    Some(value) if value == @core_bench.DASHBOARD_OS => value
    Some(value) =>
      fail(
        "Invalid --os value: \{value}. Expected \{@core_bench.DASHBOARD_OS}.",
      )
  }
}

///|
fn parse_backends(value : String?) -> Array[@core_bench.Backend] raise {
  let raw = match value {
    Some(value) => value
    None => @core_bench.backends().map(backend => backend.name()).join(",")
  }
  let backends = []
  for item in raw.split(",") {
    let item = item.trim().to_owned()
    if item.is_empty() {
      continue
    }
    match @core_bench.Backend::parse(item) {
      Some(backend) => backends.push(backend)
      None => {
        let expected = @core_bench.backends()
          .map(backend => backend.name())
          .join(", ")
        fail("Invalid backend: \{item}. Expected one of \{expected}.")
      }
    }
  }
  backends
}

///|
fn collect_command() -> @argparse.Command {
  @argparse.Command(
    "collect",
    about="Run moon bench against a checked-out moonbitlang/core tree",
    options=[
      @argparse.OptionArg(
        "core-dir",
        long="core-dir",
        about="Path to a moonbitlang/core checkout",
        required=true,
      ),
      @argparse.OptionArg(
        "os",
        long="os",
        about="Platform to publish [default: \{@core_bench.DASHBOARD_OS}]",
      ),
      @argparse.OptionArg(
        "backends",
        long="backends",
        about="Comma-separated backends [default: wasm,wasm-gc,js,native]",
      ),
      @argparse.OptionArg(
        "out-dir",
        long="out-dir",
        about="Output directory [default: data/core-bench/current/<os>]",
      ),
      @argparse.OptionArg(
        "bench-timeout-seconds",
        long="bench-timeout-seconds",
        about="Timeout per backend [default: \{DEFAULT_BENCH_TIMEOUT_SECONDS}]",
      ),
    ],
  )
}

///|
async fn run_collect(matches : @argparse.Matches) -> Unit {
  guard option_value(matches, "core-dir") is Some(core_dir) else {
    fail("--core-dir is required.")
  }
  let os = parse_os(option_value(matches, "os"))
  let out_dir = option_or(
    matches,
    "out-dir",
    join(join(DEFAULT_DATA_DIR, "current"), os),
  )
  let options : CollectOptions = {
    core_dir,
    os,
    backends: parse_backends(option_value(matches, "backends")),
    out_dir,
    bench_timeout_seconds: option_int(
      matches,
      "bench-timeout-seconds",
      DEFAULT_BENCH_TIMEOUT_SECONDS,
    ),
  }
  let (metadata, records) = collect_core_bench(options)
  let path = join(out_dir, "data.jsonl")
  write_file(path, @core_bench.stringify_jsonl(metadata, records))
  println("Wrote \{records.length()} core benchmark records to \{path}")
}

///|
fn update_history_command() -> @argparse.Command {
  @argparse.Command(
    "update-history",
    about="Add the current day to history and prune to the retention window",
    options=[
      @argparse.OptionArg(
        "data-dir",
        long="data-dir",
        about="Core benchmark data directory [default: \{DEFAULT_DATA_DIR}]",
      ),
      @argparse.OptionArg(
        "date",
        long="date",
        about="History date as YYYY-MM-DD [default: today UTC]",
      ),
      @argparse.OptionArg(
        "retention-days",
        long="retention-days",
        about="Retained calendar days [default: \{DEFAULT_HISTORY_RETENTION_DAYS}]",
      ),
    ],
  )
}

///|
async fn run_update_history(matches : @argparse.Matches) -> Unit {
  let (index, folded) = update_history(
    option_or(matches, "data-dir", DEFAULT_DATA_DIR),
    match option_value(matches, "date") {
      Some(date) => date
      None => today_utc()
    },
    option_int(matches, "retention-days", DEFAULT_HISTORY_RETENTION_DAYS),
  )
  if folded {
    println(
      "Updated core benchmark history with \{index.days.length()} retained days.",
    )
  } else {
    println(
      "No successful measurements today; history unchanged " +
      "(\{index.days.length()} retained days).",
    )
  }
}

///|
fn update_events_command() -> @argparse.Command {
  @argparse.Command(
    "update-events",
    about="Open, carry, and close outstanding regression events",
    options=[
      @argparse.OptionArg(
        "data-dir",
        long="data-dir",
        about="Core benchmark data directory [default: \{DEFAULT_DATA_DIR}]",
      ),
      @argparse.OptionArg(
        "notes-dir",
        long="notes-dir",
        about="Regression note directory [default: \{DEFAULT_NOTES_DIR}]",
      ),
    ],
  )
}

///|
async fn run_update_events(matches : @argparse.Matches) -> Unit {
  let (events, opened, closed, noted) = update_regression_events(
    option_or(matches, "data-dir", DEFAULT_DATA_DIR),
    option_or(matches, "notes-dir", DEFAULT_NOTES_DIR),
  )
  println(
    "\{events.length()} outstanding regressions " +
    "(\{opened} opened, \{closed} closed, \{noted} noted).",
  )
}

///|
fn note_command() -> @argparse.Command {
  @argparse.Command(
    "note",
    about="Record what a human concluded about an outstanding regression",
    options=[
      @argparse.OptionArg(
        "match",
        long="match",
        about="Part of the benchmark label, package, or file",
        required=true,
      ),
      @argparse.OptionArg(
        "text",
        long="text",
        about="What was concluded, and on what evidence",
        required=true,
      ),
      @argparse.OptionArg(
        "backend",
        long="backend",
        about="Narrow to one backend [default: every backend]",
      ),
      @argparse.OptionArg(
        "data-dir",
        long="data-dir",
        about="Core benchmark data directory [default: \{DEFAULT_DATA_DIR}]",
      ),
      @argparse.OptionArg(
        "notes-dir",
        long="notes-dir",
        about="Regression note directory [default: \{DEFAULT_NOTES_DIR}]",
      ),
    ],
  )
}

///|
async fn run_note(matches : @argparse.Matches) -> Unit {
  guard option_value(matches, "match") is Some(keyword) else {
    fail("--match is required.")
  }
  guard option_value(matches, "text") is Some(text) else {
    fail("--text is required.")
  }
  let backend = match option_value(matches, "backend") {
    None => None
    Some(value) =>
      match @core_bench.Backend::parse(value) {
        Some(backend) => Some(backend)
        None => {
          let expected = @core_bench.backends()
            .map(backend => backend.name())
            .join(", ")
          fail("Invalid backend: \{value}. Expected one of \{expected}.")
        }
      }
  }
  let path = write_note(
    option_or(matches, "data-dir", DEFAULT_DATA_DIR),
    option_or(matches, "notes-dir", DEFAULT_NOTES_DIR),
    backend,
    keyword,
    text,
  )
  println("Wrote \{path}")
}

///|
fn status_badge_command() -> @argparse.Command {
  @argparse.Command("status-badge", about="Write the dashboard status badge", options=[
    @argparse.OptionArg(
      "data-dir",
      long="data-dir",
      about="Core benchmark data directory [default: \{DEFAULT_DATA_DIR}]",
    ),
    @argparse.OptionArg(
      "out",
      long="out",
      about="Badge SVG output path [default: <data-dir>/status.svg]",
    ),
  ])
}

///|
async fn run_status_badge(matches : @argparse.Matches) -> Unit {
  let data_dir = option_or(matches, "data-dir", DEFAULT_DATA_DIR)
  let out_path = option_or(matches, "out", join(data_dir, "status.svg"))
  let data = read_dashboard_data(data_dir)
  let summary = @core_bench.summarize_dashboard_status(data)
  write_file(out_path, @core_bench.render_dashboard_status_svg(summary))
  println(
    "Wrote \{summary.status} dashboard badge to \{out_path} " +
    "(\{summary.regression_count} regressions, \{summary.error_count} errors).",
  )
}

///|
async fn main {
  try {
    let matches = @argparse.Command(
      "dashboard",
      about="Collect and publish MoonBit core benchmark results.",
      subcommand_required=true,
      subcommands=[
        collect_command(),
        update_history_command(),
        update_events_command(),
        note_command(),
        status_badge_command(),
      ],
    ).parse()
    guard matches.subcommand is Some((name, sub)) else {
      fail("No subcommand specified.")
    }
    match name {
      "collect" => run_collect(sub)
      "update-history" => run_update_history(sub)
      "update-events" => run_update_events(sub)
      "note" => run_note(sub)
      "status-badge" => run_status_badge(sub)
      _ => fail("Unknown subcommand: \{name}")
    }
  } catch {
    error => {
      @stdio.stderr.write("\{error}\n")
      @sys.exit(1)
    }
  }
}
