// Restoring published history, folding the current day into it, and pruning.

///|
pub const DEFAULT_HISTORY_RETENTION_DAYS : Int = 14

///|
const PUBLISHED_PREFIX : String = "data/core-bench/"

///|
/// `YYYY-MM-DD`
const DATE : Regex = re"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"

///|
fn is_date(value : String) -> Bool {
  DATE.execute(value) is Some(_)
}

///|
fn normalize_base_url(value : String) -> String {
  value.trim().trim_end(chars="/").to_owned()
}

///|
/// A published path, relative to the local data directory.
fn strip_published_prefix(path : String) -> String {
  match path.strip_prefix(PUBLISHED_PREFIX) {
    Some(rest) => rest.to_owned()
    None => path
  }
}

///|
/// Fetch a published file, treating every failure as absence.
///
/// The body is drained a chunk at a time rather than through `read_all`, which
/// raises `ReaderClosed` partway through a large chunked response. A day of
/// published benchmark data is close to a megabyte, so every day would
/// otherwise silently fail to restore.
async fn fetch_text(url : String) -> String? {
  try {
    let (response, client) = @http.get_stream(url)
    defer client.close()
    if response.code < 200 || response.code >= 300 {
      return None
    }
    let body = Buffer()
    while client.read_some() is Some(chunk) {
      body.write_bytes(chunk)
    }
    Some(@utf8.decode(body.to_bytes()))
  } catch {
    _ => None
  }
}

///|
async fn copy_log_from_published(
  base_url : String,
  data_dir : String,
  path : String,
) -> Unit {
  guard fetch_text("\{base_url}/\{path}") is Some(text) else { return }
  write_file(join(data_dir, strip_published_prefix(path)), text)
}

///|
/// Pull the published history back down so this run can extend it.
///
/// Returns early with zero when the index cannot be fetched, which is how
/// `docs/operations.md` breaks the history chain on a platform change.
pub async fn restore_published_history(
  base_url_value : String,
  data_dir : String,
) -> Int {
  let base_url = normalize_base_url(base_url_value)
  if base_url.is_empty() {
    return 0
  }
  guard fetch_text("\{base_url}/\{PUBLISHED_PREFIX}history/index.json")
    is Some(index_text) else {
    return 0
  }
  let index : @core_bench.HistoryIndex = @json.from_string(index_text)
  ensure_dir(join(data_dir, "history"))
  write_file(join3(data_dir, "history", "index.json"), pretty_json(index_text))
  let mut restored = 0
  for day in index.days {
    guard fetch_text("\{base_url}/\{day.path}") is Some(jsonl_text) else {
      continue
    }
    write_file(join(data_dir, strip_published_prefix(day.path)), jsonl_text)
    restored += 1
    // A day holds a thousand records but only eight logs, two per backend.
    // Fetching per record would ask for the same file a thousand times over.
    let log_paths : Set[String] = Set([])
    for record in @core_bench.parse_jsonl(jsonl_text).records {
      if record.stdout_path is Some(path) {
        log_paths.add(path)
      }
      if record.stderr_path is Some(path) {
        log_paths.add(path)
      }
    }
    for path in log_paths {
      copy_log_from_published(base_url, data_dir, path)
    }
  }
  restored
}

///|
/// A current-day log path, as it will read once the day is history.
fn rewrite_path_to_history(
  path : String?,
  date : String,
  data_dir : String,
) -> String? {
  path.map(path => {
    join(
      join3(join3(data_dir, "history", date), @core_bench.DASHBOARD_OS, "logs"),
      basename(path),
    )
  })
}

///|
async fn copy_current_logs_to_history(date : String, data_dir : String) -> Unit {
  let current = join3(
    join(data_dir, "current"),
    @core_bench.DASHBOARD_OS,
    "logs",
  )
  let target = join3(
    join3(data_dir, "history", date),
    @core_bench.DASHBOARD_OS,
    "logs",
  )
  let is_directory = try (@fs.kind(current) is Directory) catch {
    _ => false
  }
  if !is_directory {
    return
  }
  ensure_dir(target)
  for name in @fs.readdir(current) {
    let source = join(current, name)
    if @fs.kind(source) is Regular {
      @fs.write_file(
        join(target, name),
        @fs.read_file(source),
        create_mode=CreateOrTruncate,
      )
    }
  }
}

///|
/// Every retained calendar day already on disk, in date order.
async fn list_history_dates(data_dir : String) -> Array[String] {
  let history = join(data_dir, "history")
  let is_directory = try (@fs.kind(history) is Directory) catch {
    _ => false
  }
  if !is_directory {
    return []
  }
  let dates = []
  for name in @fs.readdir(history) {
    if is_date(name) && @fs.kind(join(history, name)) is Directory {
      dates.push(name)
    }
  }
  dates.sort_by((left, right) => left.lexical_compare(right))
  dates
}

///|
async fn remove_pruned_dates(data_dir : String, keep : Set[String]) -> Unit {
  for date in list_history_dates(data_dir) {
    if !keep.contains(date) {
      @fs.rmdir(join3(data_dir, "history", date), recursive=true) catch {
        _ => ()
      }
    }
  }
}

///|
/// Fold the current day into history, prune to the retention window, and
/// rewrite the index.
pub async fn update_history(
  data_dir : String,
  date : String,
  retention_days : Int,
) -> @core_bench.HistoryIndex {
  if !is_date(date) {
    fail("Invalid history date: \{date}")
  }
  let current_path = join3(
    join(data_dir, "current"),
    @core_bench.DASHBOARD_OS,
    "data.jsonl",
  )
  let current = read_jsonl_file(current_path)
  guard current.metadata is Some(metadata) else {
    fail("Current data is missing metadata: \{current_path}")
  }
  copy_current_logs_to_history(date, data_dir)
  let history_records = current.records.map(record => {
    ..record,
    stdout_path: rewrite_path_to_history(record.stdout_path, date, data_dir),
    stderr_path: rewrite_path_to_history(record.stderr_path, date, data_dir),
  })
  let history_data_path = join3(
    join3(data_dir, "history", date),
    @core_bench.DASHBOARD_OS,
    "data.jsonl",
  )
  write_file(
    history_data_path,
    @core_bench.stringify_jsonl(metadata, history_records),
  )
  let dates = list_history_dates(data_dir)
  let keep_dates = if dates.length() <= retention_days {
    dates
  } else {
    dates[dates.length() - retention_days:].to_owned()
  }
  remove_pruned_dates(data_dir, Set(keep_dates))
  let index : @core_bench.HistoryIndex = {
    generated_at: iso_now(),
    retention_days,
    days: keep_dates.map(history_date => {
      date: history_date,
      os: @core_bench.DASHBOARD_OS,
      path: join3(
        join3(data_dir, "history", history_date),
        @core_bench.DASHBOARD_OS,
        "data.jsonl",
      ),
    }),
  }
  ensure_dir(join(data_dir, "history"))
  write_file(
    join3(data_dir, "history", "index.json"),
    pretty_json(@json.to_string(index)),
  )
  index
}

///|
/// Read the current day and every retained day into one dashboard view.
pub async fn read_dashboard_data(
  data_dir : String,
) -> @core_bench.DashboardData {
  let current = read_jsonl_file(
    join3(join(data_dir, "current"), @core_bench.DASHBOARD_OS, "data.jsonl"),
  )
  let index_path = join3(data_dir, "history", "index.json")
  let index : @core_bench.HistoryIndex? = Some(
    @json.from_string(@fs.read_file(index_path).text()),
  ) catch {
    _ => None
  }
  let history = []
  if index is Some(index) {
    for day in index.days {
      history.push(
        (
          { date: day.date, data: read_jsonl_file(day.path) } :
          @core_bench.HistoryEntry),
      )
    }
  }
  { current, history, history_index: index }
}
