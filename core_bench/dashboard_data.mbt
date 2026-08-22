// Turning published JSONL into the rows the dashboard and the badge both read.
//
// A row is one benchmark identity across every backend. Its cells compare the
// current day with the most recent retained day strictly before it, and its
// series carries every retained day in date order.

///|
/// Which rows the dashboard is showing.
pub(all) enum Filter {
  AllRows
  ByState(CellState)
} derive(Eq, Debug)

///|
/// One backend's column in a row.
pub(all) struct BackendCell {
  backend : Backend
  current : Record?
  previous : Record?
  state : CellState
  delta_ratio : Double?
  delta_percent : Double?
} derive(Eq, Debug)

///|
/// One retained day's value for a backend.
pub(all) struct SeriesPoint {
  date : String
  record : Record?
} derive(Eq, Debug)

///|
/// One benchmark identity, across every backend.
pub(all) struct Row {
  key : String
  pkg : String
  file : String
  line : Int
  block_label : String
  case_name : String
  cells : Map[Backend, BackendCell]
  series : Map[Backend, Array[SeriesPoint]]
  state : CellState
  regression_count : Int
  improvement_count : Int
  error_count : Int
  missing_count : Int
  new_count : Int
  stable_count : Int
} derive(Eq, Debug)

///|
pub(all) struct HistoryEntry {
  date : String
  data : Jsonl
} derive(Eq, Debug)

///|
/// Everything the dashboard reads: the current day, and retained history.
pub(all) struct DashboardData {
  current : Jsonl
  history : Array[HistoryEntry]
  history_index : HistoryIndex?
} derive(Eq, Debug)

///|
pub fn DashboardData::empty() -> DashboardData {
  { current: Jsonl::empty(), history: [], history_index: None }
}

///|
/// How many rows fall into each filter.
pub(all) struct RowCounts {
  all : Int
  regression : Int
  improvement : Int
  new_ : Int
  missing : Int
  error : Int
  stable : Int
} derive(Eq, Debug)

///|
/// Worst state first, so what needs attention sorts to the top.
fn state_priority(state : CellState) -> Int {
  match state {
    Errored => 0
    Regression => 1
    Missing => 2
    New => 3
    Improvement => 4
    Stable => 5
  }
}

///|
/// What makes a benchmark the same benchmark across days and backends.
pub fn identity_key(record : Record) -> String {
  [
    record.pkg,
    record.file,
    record.line.to_string(),
    record.block_label,
    record.case_name,
  ].join("\u{0}")
}

///|
/// The verdict on one backend's current timing.
pub(all) struct Delta {
  state : CellState
  ratio : Double?
  percent : Double?
} derive(Eq, Debug)

///|
/// Compare one current timing against the previous retained day.
///
/// A five percent move either way is the threshold, matching the badge.
pub fn classify_delta(current : Record?, previous : Record?) -> Delta {
  guard current is Some(current) else {
    return { state: Missing, ratio: None, percent: None }
  }
  if current.status is Failed {
    return { state: Errored, ratio: None, percent: None }
  }
  guard previous is Some(previous) else {
    return { state: New, ratio: None, percent: None }
  }
  guard previous.status is Succeeded else {
    return { state: New, ratio: None, percent: None }
  }
  guard previous.mean_us is Some(previous_mean) else {
    return { state: New, ratio: None, percent: None }
  }
  guard current.mean_us is Some(current_mean) else {
    return { state: New, ratio: None, percent: None }
  }
  let ratio = current_mean / previous_mean
  let percent = (ratio - 1.0) * 100.0
  let state = if ratio >= 1.05 {
    Regression
  } else if ratio <= 0.95 {
    Improvement
  } else {
    Stable
  }
  { state, ratio: Some(ratio), percent: Some(percent) }
}

///|
/// Index one day's records by identity and backend.
fn index_by_identity(
  records : Array[Record],
) -> Map[String, Map[Backend, Record]] {
  let index : Map[String, Map[Backend, Record]] = Map([])
  for record in records {
    let key = identity_key(record)
    let by_backend = match index.get(key) {
      Some(existing) => existing
      None => {
        let fresh : Map[Backend, Record] = Map([])
        index[key] = fresh
        fresh
      }
    }
    by_backend[record.backend] = record
  }
  index
}

///|
/// Retained history in date order.
///
/// `String::compare` orders by length first, so every ordering here uses
/// `lexical_compare`: the dashboard's dates, paths, and labels must sort the
/// way a reader expects to read them.
fn sorted_history(data : DashboardData) -> Array[HistoryEntry] {
  let days = data.history.copy()
  days.sort_by((left, right) => left.date.lexical_compare(right.date))
  days
}

///|
/// The most recent retained day strictly before the current one.
fn latest_previous_day(data : DashboardData) -> HistoryEntry? {
  let days = sorted_history(data)
  let candidates = match data.current.metadata {
    Some(metadata) => {
      let current_date = metadata.generated_at[0:10].to_owned()
      days.filter(day => day.date.lexical_compare(current_date) < 0)
    }
    None => days
  }
  candidates.last()
}

///|
fn count_cells(cells : Array[BackendCell], state : CellState) -> Int {
  cells.filter(cell => cell.state == state).length()
}

///|
/// Build every row the dashboard shows, worst state first.
pub fn build_rows(data : DashboardData) -> Array[Row] {
  let history = sorted_history(data)
  let previous_day = latest_previous_day(data)
  let current_index = index_by_identity(data.current.records)
  let previous_index : Map[String, Map[Backend, Record]] = match previous_day {
    Some(day) => index_by_identity(day.data.records)
    None => Map([])
  }
  let history_index = history.map(day => {
    (day.date, index_by_identity(day.data.records))
  })

  // Every identity seen anywhere gets a row, so a benchmark that disappeared
  // reads as missing rather than vanishing from the table.
  let identities = []
  let seen = Set([])
  fn remember(record : Record) -> Unit {
    let key = identity_key(record)
    if !seen.contains(key) {
      seen.add(key)
      identities.push(record)
    }
  }

  for record in data.current.records {
    remember(record)
  }
  if previous_day is Some(day) {
    for record in day.data.records {
      remember(record)
    }
  }
  for day in history {
    for record in day.data.records {
      remember(record)
    }
  }

  let rows = identities.map(record => {
    let key = identity_key(record)
    let cells : Map[Backend, BackendCell] = Map([])
    let series : Map[Backend, Array[SeriesPoint]] = Map([])
    for backend in backends() {
      let current = current_index.get(key).bind(by => by.get(backend))
      let previous = previous_index.get(key).bind(by => by.get(backend))
      let delta = classify_delta(current, previous)
      cells[backend] = {
        backend,
        current,
        previous,
        state: delta.state,
        delta_ratio: delta.ratio,
        delta_percent: delta.percent,
      }
      series[backend] = history_index.map(entry => {
        let (date, index) = entry
        { date, record: index.get(key).bind(by => by.get(backend)) }
      })
    }
    let all_cells = backends().filter_map(backend => cells.get(backend))
    let regression_count = count_cells(all_cells, Regression)
    let improvement_count = count_cells(all_cells, Improvement)
    let error_count = count_cells(all_cells, Errored)
    let missing_count = count_cells(all_cells, Missing)
    let new_count = count_cells(all_cells, New)
    let stable_count = count_cells(all_cells, Stable)
    let state = if error_count > 0 {
      Errored
    } else if regression_count > 0 {
      Regression
    } else if missing_count > 0 {
      Missing
    } else if new_count > 0 {
      New
    } else if improvement_count > 0 {
      Improvement
    } else {
      Stable
    }
    {
      key,
      pkg: record.pkg,
      file: record.file,
      line: record.line,
      block_label: record.block_label,
      case_name: record.case_name,
      cells,
      series,
      state,
      regression_count,
      improvement_count,
      error_count,
      missing_count,
      new_count,
      stable_count,
    }
  })
  rows.sort_by((left, right) => {
    let priority = state_priority(left.state) - state_priority(right.state)
    if priority != 0 {
      return priority
    }
    let by_package = left.pkg.lexical_compare(right.pkg)
    if by_package != 0 {
      return by_package
    }
    let by_file = left.file.lexical_compare(right.file)
    if by_file != 0 {
      return by_file
    }
    let by_line = left.line - right.line
    if by_line != 0 {
      return by_line
    }
    let by_label = left.block_label.lexical_compare(right.block_label)
    if by_label != 0 {
      return by_label
    }
    left.case_name.lexical_compare(right.case_name)
  })
  rows
}

///|
/// Every cell of a row, in display order.
pub fn Row::backend_cells(self : Row) -> Array[BackendCell] {
  backends().filter_map(backend => self.cells.get(backend))
}

///|
/// Rows matching the active filter and search keyword.
pub fn filter_rows(
  rows : Array[Row],
  filter : Filter,
  search : String,
) -> Array[Row] {
  let keyword = search.trim().to_lower()
  rows.filter(row => {
    let matches_filter = match filter {
      AllRows => true
      ByState(state) =>
        row.state == state ||
        row.backend_cells().any(cell => cell.state == state)
    }
    if !matches_filter {
      return false
    }
    if keyword.is_empty() {
      return true
    }
    let haystack = "\{row.pkg} \{row.file} \{row.line} \{row.block_label} \{row.case_name}"
    haystack.to_lower().contains(keyword)
  })
}

///|
/// How many rows fall into each filter.
pub fn count_rows(rows : Array[Row]) -> RowCounts {
  {
    all: rows.length(),
    regression: rows.filter(row => row.regression_count > 0).length(),
    improvement: rows.filter(row => row.improvement_count > 0).length(),
    new_: rows.filter(row => row.new_count > 0).length(),
    missing: rows.filter(row => row.missing_count > 0).length(),
    error: rows.filter(row => row.error_count > 0).length(),
    stable: rows.filter(row => row.state is Stable).length(),
  }
}

///|
/// Whether the current day carries anything the badge should go red for.
pub fn has_current_regression_or_error(data : DashboardData) -> Bool {
  build_rows(data).any(row => {
    row.backend_cells().any(cell => cell.state is (Regression | Errored))
  })
}
