// Small helpers shared by the collector and the history commands.

///|
/// The published data directory, relative to the repository root.
const DEFAULT_DATA_DIR : String = "data/core-bench"

///|
fn join(base : String, rest : String) -> String {
  @path.Path(base).join(@path.Path(rest)).to_string()
}

///|
fn join3(base : String, second : String, third : String) -> String {
  join(join(base, second), third)
}

///|
fn dirname(path : String) -> String {
  @path.Path(path).dirname().to_string()
}

///|
fn basename(path : String) -> String {
  @path.Path(path).basename().to_owned()
}

///|
/// The current instant, in the same shape as `Date.prototype.toISOString`.
fn iso_now() -> String raise {
  let millis = @env.now().reinterpret_as_int64()
  @time.unix(
    millis / 1000L,
    nanosecond=(millis % 1000L * 1000000L).to_int(),
    zone=@time.utc_zone,
  ).to_string()
}

///|
/// Today's UTC calendar date.
fn today_utc() -> String raise {
  iso_now()[0:10].to_owned()
}

///|
/// An environment variable, treating unset and empty alike.
fn env_or(name : String, fallback : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if !value.is_empty() => value
    _ => fallback
  }
}

///|
/// The first `limit` code units of a string.
fn head(value : String, limit : Int) -> String {
  if value.length() <= limit {
    value
  } else {
    value[0:limit].to_owned()
  }
}

///|
/// Read a `data.jsonl`, treating a missing file as an empty one.
async fn read_jsonl_file(path : String) -> @core_bench.Jsonl {
  let text = @fs.read_file(path).text() catch {
    _ => return @core_bench.Jsonl::empty()
  }
  @core_bench.parse_jsonl(text)
}

///|
/// Create a directory and every parent, tolerating one that already exists.
///
/// `@fs.mkdir(recursive=true)` creates parents but still fails on an existing
/// leaf, and every caller here means "make sure this exists".
async fn ensure_dir(path : String) -> Unit {
  let exists = try (@fs.kind(path) is Directory) catch {
    _ => false
  }
  if exists {
    return
  }
  @fs.mkdir(path, recursive=true)
}

///|
/// Write a file, creating every directory above it.
async fn write_file(path : String, contents : String) -> Unit {
  ensure_dir(dirname(path))
  @fs.write_file(path, contents, create_mode=CreateOrTruncate)
}

///|
/// Render as `JSON.stringify(value, null, 2)` does, with a trailing newline.
fn pretty_json(text : String) -> String raise {
  "\{@core_json.parse(text).stringify(indent=2)}\n"
}
