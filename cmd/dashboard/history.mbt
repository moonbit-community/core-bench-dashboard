// Folding the current day into history, pruning it, and reading it back.

///|
pub const DEFAULT_HISTORY_RETENTION_DAYS : Int = 14

///|
/// `YYYY-MM-DD`
const DATE : Regex = re"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"

///|
fn is_date(value : String) -> Bool {
  DATE.execute(value) is Some(_)
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
///
/// A day that measured nothing is not folded. When `moon bench` fails for every
/// backend the current day holds only failure records, and writing that as
/// history makes it the day everything after it is compared against: every
/// benchmark then reads `new`, because the day it should have been measured
/// against has no record of it. A day with no measurements is not a data point,
/// so it is left out and the next run compares against the last day that
/// actually measured something. The failure is still reported — it is in
/// `current/`, in the run log, and in the badge.
///
/// Returns the index and whether the day was folded.
pub async fn update_history(
  data_dir : String,
  date : String,
  retention_days : Int,
) -> (@core_bench.HistoryIndex, Bool) {
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
  let measured = current.records.any(record => record.status is Succeeded)
  if measured {
    fold_current_into_history(date, data_dir, metadata, current.records)
  }
  let index = rewrite_history_index(data_dir, retention_days)
  (index, measured)
}

///|
/// Write the current day under `history/<date>/`, logs included.
async fn fold_current_into_history(
  date : String,
  data_dir : String,
  metadata : @core_bench.Metadata,
  records : Array[@core_bench.Record],
) -> Unit {
  copy_current_logs_to_history(date, data_dir)
  let history_records = records.map(record => {
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
}

///|
/// Prune to the retention window and rewrite `history/index.json`.
async fn rewrite_history_index(
  data_dir : String,
  retention_days : Int,
) -> @core_bench.HistoryIndex {
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
