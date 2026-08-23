// The Core Benchmark Dashboard, in the browser.
//
// Three pieces of state, deliberately kept apart: the published data, which
// changes only while loading; the view controls, which change on every
// keystroke; and the log document being fetched. Rows are rebuilt when the data
// changes, not when the search box does.

///|
const CURRENT_PATH : String = "data/core-bench/current/\{@core_bench.DASHBOARD_OS}/data.jsonl"

///|
const HISTORY_INDEX_PATH : String = "data/core-bench/history/index.json"

///|
const EVENTS_PATH : String = "data/core-bench/events.json"

// ---------------------------------------------------------------- data state

///|
priv struct DataModel {
  data : @core_bench.DashboardData
  events : Array[@core_bench.RegressionEvent]
  loading : Bool
  pending_days : Int
} derive(Eq)

///|
priv enum DataMsg {
  EventsLoaded(Result[String, Error])
  CurrentLoaded(Result[String, Error])
  IndexLoaded(Result[String, Error])
  DayLoaded(String, Result[String, Error])
}

///|
/// Parse a fetched document, treating any failure as no data at all.
fn parse_or_empty(result : Result[String, Error]) -> @core_bench.Jsonl {
  guard result is Ok(text) else { return @core_bench.Jsonl::empty() }
  @core_bench.parse_jsonl(text) catch {
    _ => @core_bench.Jsonl::empty()
  }
}

///|
fn parse_events(
  result : Result[String, Error],
) -> Array[@core_bench.RegressionEvent] {
  guard result is Ok(text) else { return [] }
  @data_json.from_string(text) catch {
    _ => []
  }
}

///|
fn parse_index(result : Result[String, Error]) -> @core_bench.HistoryIndex? {
  guard result is Ok(text) else { return None }
  Some(@data_json.from_string(text)) catch {
    _ => None
  }
}

///|
fn fetch_text(
  path : String,
  emit : @cmd.Emit[Result[String, Error]],
) -> @cmd.Cmd {
  @http.get(site_url(path)).expect_text(emit)
}

///|
fn update_data(
  model : DataModel,
  msg : DataMsg,
  emit : @cmd.Emit[DataMsg],
) -> (DataModel, @cmd.Cmd) {
  match msg {
    EventsLoaded(result) =>
      (
        { ..model, events: parse_events(result) },
        fetch_text(CURRENT_PATH, emit.map(result => CurrentLoaded(result))),
      )
    CurrentLoaded(result) =>
      (
        { ..model, data: { ..model.data, current: parse_or_empty(result) } },
        fetch_text(HISTORY_INDEX_PATH, emit.map(result => IndexLoaded(result))),
      )
    IndexLoaded(result) => {
      guard parse_index(result) is Some(index) else {
        return ({ ..model, loading: false }, @cmd.none)
      }
      if index.days.is_empty() {
        return (
          {
            ..model,
            loading: false,
            data: { ..model.data, history_index: Some(index) },
          },
          @cmd.none,
        )
      }
      (
        {
          ..model,
          pending_days: index.days.length(),
          data: { ..model.data, history_index: Some(index) },
        },
        @cmd.batch(
          index.days.map(day => {
            fetch_text(
              day.path,
              emit.map(result => DayLoaded(day.date, result)),
            )
          }),
        ),
      )
    }
    DayLoaded(date, result) => {
      let history = model.data.history.copy()
      history.push({ date, data: parse_or_empty(result) })
      let pending_days = model.pending_days - 1
      (
        {
          ..model,
          data: { ..model.data, history, },
          pending_days,
          loading: pending_days > 0,
        },
        @cmd.none,
      )
    }
  }
}

// ------------------------------------------------------------ view controls

///|
priv struct UiModel {
  filter : @core_bench.Filter
  search : String
  expanded : @sorted_set.SortedSet[String]
} derive(Eq)

///|
priv enum UiMsg {
  SetFilter(@core_bench.Filter)
  SetSearch(String)
  ToggleExpand(String)
}

///|
fn update_ui(model : UiModel, msg : UiMsg) -> UiModel {
  match msg {
    SetFilter(filter) => { ..model, filter, }
    SetSearch(search) => { ..model, search, }
    ToggleExpand(key) =>
      if model.expanded.contains(key) {
        { ..model, expanded: model.expanded.remove(key) }
      } else {
        { ..model, expanded: model.expanded.add(key) }
      }
  }
}

// -------------------------------------------------------------------- view

///|
fn state_badge(state : @core_bench.CellState) -> @html.Html {
  let color = state_color(state)
  @html.span(
    style=[
      "display: inline-flex",
      "min-width: 44px",
      "justify-content: center",
      "border: 1px solid \{color.border}",
      "border-radius: 4px",
      "background: \{color.background}",
      "color: \{color.foreground}",
      "padding: 2px 5px",
      "font-size: 10px",
      "font-weight: 800",
    ],
    state_label(state),
  )
}

///|
fn backend_cell(
  row : @core_bench.Row,
  backend : @core_bench.Backend,
  emit : @cmd.Emit[LogMsg],
) -> @html.Html {
  let cell = row.cells.get(backend)
  let state = match cell {
    Some(cell) => cell.state
    None => Missing
  }
  let color = state_color(state)
  let record = cell.bind(cell => cell.current)
  let delta = cell.bind(cell => cell.delta_percent)
  // A `td` takes no click handler, so the padding moves onto an inner div and
  // that div carries the handler. The clickable area is still the whole cell.
  @html.td(
    title="\{backend} \{state} \{format_delta(delta)}",
    style=[
      "border: 1px solid \{color.border}",
      "background: \{color.background}",
      "color: \{color.foreground}",
      "padding: 0",
      "text-align: right",
    ],
    [
      @html.div(
        on_click=match record {
          Some(record) => emit(Open(Some(record), "\{backend} current"))
          None => @cmd.none
        },
        style=[
          "padding: 6px",
          "cursor: \{if record is Some(_) { "pointer" } else { "default" }}",
        ],
        [
          @html.div(
            style=[
              "display: flex", "align-items: center", "justify-content: space-between",
              "gap: 6px",
            ],
            [
              state_badge(state),
              @html.div(
                style=[MONO, "font-weight: 800"],
                format_time(record.bind(record => record.mean_us)),
              ),
            ],
          ),
          @html.div(
            style=["margin-top: 3px", "font-size: 11px", "font-weight: 700"],
            format_delta(delta),
          ),
        ],
      ),
    ],
  )
}

///|
fn series_cell(
  point : @core_bench.SeriesPoint,
  emit : @cmd.Emit[LogMsg],
) -> @html.Html {
  let label = match point.record {
    Some(record) if record.status is Failed => "ERR"
    Some(record) => format_time(record.mean_us)
    None => "-"
  }
  let background = match point.record {
    Some(record) if record.status is Failed => "#fee2e2"
    Some(_) => "#ffffff"
    None => "#f3f4f6"
  }
  @html.button(
    type_="button",
    title=point.date,
    on_click=match point.record {
      Some(record) =>
        emit(Open(Some(record), "\{point.date} \{record.backend}"))
      None => @cmd.none
    },
    style=[
      "width: 100%",
      "min-height: 26px",
      BORDER,
      "border-radius: 4px",
      "background: \{background}",
      "color: #111827",
      "cursor: \{if point.record is Some(_) { "pointer" } else { "default" }}",
      "font-size: 11px",
      MONO,
    ],
    label,
  )
}

///|
/// The per-backend history strip revealed under an expanded row.
fn expanded_row(row : @core_bench.Row, emit : @cmd.Emit[LogMsg]) -> @html.Html {
  let dates = match row.series.get(@core_bench.backends()[0]) {
    Some(points) => points.map(point => point.date)
    None => []
  }
  let columns = if dates.is_empty() { 1 } else { dates.length() }
  let cells = []
  cells.push(
    @html.div(
      style=["font-size: 11px", "font-weight: 800", "color: #374151"],
      "Backend",
    ),
  )
  for date in dates {
    cells.push(
      @html.div(
        style=[
          "font-size: 11px", "font-weight: 800", "color: #374151", "text-align: center",
        ],
        date[5:].to_owned(),
      ),
    )
  }
  for backend in @core_bench.backends() {
    cells.push(@html.div(style=[MONO, "font-weight: 800"], backend.name()))
    for point in row.series.get(backend).unwrap_or([]) {
      cells.push(series_cell(point, emit))
    }
  }
  @html.div(
    style=[
      "padding: 10px 12px", "background: #f9fafb", "border-top: 1px solid #e5e7eb",
    ],
    [
      @html.div(
        style=[
          "display: grid",
          "grid-template-columns: 90px repeat(\{columns}, minmax(72px, 1fr))",
          "gap: 5px",
          "align-items: center",
        ],
        cells,
      ),
    ],
  )
}

///|
fn filter_button(
  label : String,
  filter : @core_bench.Filter,
  value : Int,
  active : @core_bench.Filter,
  emit : @cmd.Emit[UiMsg],
) -> @html.Html {
  let selected = active == filter
  @html.button(
    type_="button",
    on_click=emit(SetFilter(filter)),
    style=[
      "min-width: 104px",
      "border: 1px solid \{if selected { "#111827" } else { "#d1d5db" }}",
      "border-radius: 6px",
      "background: \{if selected { "#111827" } else { "#ffffff" }}",
      "color: \{if selected { "#ffffff" } else { "#111827" }}",
      "padding: 7px 9px",
      "cursor: pointer",
      "text-align: left",
    ],
    [
      @html.div(style=["font-size: 11px", "font-weight: 800"], label),
      @html.div(
        style=["font-size: 19px", "font-weight: 900", "line-height: 1.1"],
        value.to_string(),
      ),
    ],
  )
}

///|
fn header(metadata : @core_bench.Metadata?) -> @html.Html {
  let toolchain = match metadata {
    Some(metadata) => {
      let joined = metadata.toolchain_version.join("\n").trim().to_owned()
      if joined.is_empty() {
        "-"
      } else {
        joined
      }
    }
    None => "-"
  }
  @html.div(
    style=[
      "display: flex", "align-items: flex-start", "justify-content: space-between",
      "gap: 16px", "margin-bottom: 14px",
    ],
    [
      @html.div([
        @html.h1(
          style=["margin: 0", "font-size: 24px", "line-height: 1.15"],
          "Core Benchmark Dashboard",
        ),
        @html.div(
          style=["margin-top: 4px", "color: #4b5563", "font-size: 13px"],
          "moonbitlang/core main, \{@core_bench.DASHBOARD_OS}",
        ),
      ]),
      @html.div(
        style=[
          BORDER,
          "border-radius: 6px",
          "background: #ffffff",
          "padding: 8px 10px",
          "min-width: 360px",
          "font-size: 12px",
        ],
        [
          @html.div([
            @html.strong("Generated"),
            @html.text(" "),
            @html.time(
              datetime=metadata
                .map(metadata => metadata.generated_at)
                .unwrap_or(""),
              title=metadata
                .map(metadata => metadata.generated_at)
                .unwrap_or(""),
              format_generated_at(
                metadata.map(metadata => metadata.generated_at),
              ),
            ),
          ]),
          @html.div(style=["margin-top: 3px"], [
            @html.strong("Core"),
            @html.text(
              " \{short_commit(metadata.map(metadata => metadata.core_commit_sha))}",
            ),
          ]),
          @html.pre(
            style=[
              "margin: 5px 0 0",
              "white-space: pre-wrap",
              "overflow-wrap: anywhere",
              MONO,
              "font-size: 11px",
              "line-height: 1.35",
            ],
            toolchain,
          ),
        ],
      ),
    ],
  )
}

///|
fn table_head() -> @html.Html {
  let head = [
    @html.th(
      style=["padding: 8px", BORDER, "text-align: left", "width: 260px"],
      "Benchmark",
    ),
    @html.th(
      style=["padding: 8px", BORDER, "text-align: left", "width: 230px"],
      "Location",
    ),
  ]
  for backend in @core_bench.backends() {
    head.push(@html.th(style=["padding: 8px", BORDER], backend.name()))
  }
  head.push(@html.th(style=["padding: 8px", BORDER, "width: 76px"], "Overall"))
  head.push(@html.th(style=["padding: 8px", BORDER, "width: 78px"], "Details"))
  @html.thead([@html.tr(style=["background: #263241", "color: white"], head)])
}

///|
fn row_view(
  row : @core_bench.Row,
  index : Int,
  expanded : Bool,
  ui_emit : @cmd.Emit[UiMsg],
  log_emit : @cmd.Emit[LogMsg],
) -> Array[@html.Html] {
  let label = row_label(row)
  let cells = [
    @html.td(
      title=label,
      style=[
        "padding: 7px",
        BORDER,
        "overflow: hidden",
        "text-overflow: ellipsis",
      ],
      [
        @html.div(
          style=[
            "font-weight: 800", "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
          ],
          label,
        ),
        @html.div(
          style=[
            "margin-top: 2px",
            "color: #4b5563",
            MONO,
            "white-space: nowrap",
            "overflow: hidden",
            "text-overflow: ellipsis",
          ],
          row.pkg,
        ),
      ],
    ),
    @html.td(
      title="\{row.file}:\{row.line}",
      style=[
        "padding: 7px",
        BORDER,
        MONO,
        "overflow: hidden",
        "text-overflow: ellipsis",
      ],
      "\{row.file}:\{row.line}",
    ),
  ]
  for backend in @core_bench.backends() {
    cells.push(backend_cell(row, backend, log_emit))
  }
  cells.push(
    @html.td(style=["padding: 7px", BORDER, "text-align: center"], [
      state_badge(row.state),
    ]),
  )
  cells.push(
    @html.td(style=["padding: 7px", BORDER, "text-align: center"], [
      @html.button(
        type_="button",
        on_click=ui_emit(ToggleExpand(row.key)),
        style=[
          BORDER,
          "border-radius: 5px",
          "background: #ffffff",
          "cursor: pointer",
          "font-size: 11px",
          "padding: 4px 8px",
        ],
        if expanded {
          "Hide"
        } else {
          "Show"
        },
      ),
    ]),
  )
  let rows = [
    @html.tr(
      style=[
        "background: \{if index % 2 == 0 { "#ffffff" } else { "#f9fafb" }}",
      ],
      cells,
    ),
  ]
  if expanded {
    rows.push(
      @html.tr([
        @html.td(colspan=8, style=["padding: 0", BORDER, "border-top: 0"], [
          expanded_row(row, log_emit),
        ]),
      ]),
    )
  }
  rows
}

///|
/// One outstanding regression: what broke, when, and by how much.
fn event_row(event : @core_bench.RegressionEvent, today : String) -> @html.Html {
  let color = state_color(Regression)
  let age = days_between(event.opened_on, today)
  let since = if age == 1 {
    "since \{event.opened_on} (1 day)"
  } else {
    "since \{event.opened_on} (\{age} days)"
  }
  @html.div(
    style=[
      "display: grid", "grid-template-columns: minmax(240px, 1fr) 76px 190px 232px",
      "gap: 10px", "align-items: baseline", "padding: 7px 10px", "border-top: 1px solid #fecaca",
    ],
    [
      @html.div(
        title="\{event.pkg} — \{event.file}:\{event.line}",
        style=[
          "font-weight: 700", "white-space: nowrap", "overflow: hidden", "text-overflow: ellipsis",
        ],
        if event.case_name.is_empty() {
          event.block_label
        } else {
          "\{event.block_label} / \{event.case_name}"
        },
      ),
      @html.div(
        style=[
          MONO,
          "font-size: 11px",
          "font-weight: 700",
          "color: \{color.foreground}",
        ],
        event.backend.name(),
      ),
      @html.div(
        style=[MONO, "font-size: 11px"],
        "\{format_time(Some(event.baseline_us))} → \{format_time(Some(event.latest_us))}",
      ),
      @html.div(
        style=["font-size: 11px", "color: #4b5563", "white-space: nowrap"],
        "\{format_delta(Some(event.delta_percent()))}  \{since}",
      ),
    ],
  )
}

///|
/// Whole days between two `YYYY-MM-DD` dates, counted the calendar way.
fn days_between(from : String, to : String) -> Int {
  days_from_epoch(to) - days_from_epoch(from)
}

///|
fn days_from_epoch(date : String) -> Int {
  let year = @string.parse_int(date[0:4]) catch { _ => return 0 }
  let month = @string.parse_int(date[5:7]) catch { _ => return 0 }
  let day = @string.parse_int(date[8:10]) catch { _ => return 0 }
  // Howard Hinnant's days-from-civil: exact, and no date library needed.
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (month + 9) % 12
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// The outstanding regressions, above the table.
///
/// A cell only knows what changed last night. This panel is what is still
/// broken, measured against the value each benchmark broke from — which is why
/// a regression nobody fixed stays visible instead of going quiet.
fn events_panel(
  events : Array[@core_bench.RegressionEvent],
  today : String,
) -> @html.Html {
  if events.is_empty() {
    return @html.div(
      style=[
        BORDER,
        "border-radius: 6px",
        "background: #ffffff",
        "padding: 10px 12px",
        "margin-bottom: 12px",
        "font-size: 12px",
        "color: #4b5563",
      ],
      "No outstanding regressions.",
    )
  }
  let color = state_color(Regression)
  let heading = if events.length() == 1 {
    "1 outstanding regression"
  } else {
    "\{events.length()} outstanding regressions"
  }
  @html.div(
    style=[
      "border: 1px solid \{color.border}",
      "border-radius: 6px",
      "background: \{color.background}",
      "margin-bottom: 12px",
      "overflow: hidden",
    ],
    [
      @html.div(
        style=[
          "padding: 8px 10px",
          "font-size: 12px",
          "font-weight: 800",
          "color: \{color.foreground}",
        ],
        "\{heading} — still slower than before they broke",
      ),
      ..events.map(event => event_row(event, today)),
    ],
  )
}

///|
fn view(
  data : DataModel,
  ui : UiModel,
  rows : Array[@core_bench.Row],
  counts : @core_bench.RowCounts,
  ui_emit : @cmd.Emit[UiMsg],
  log_emit : @cmd.Emit[LogMsg],
) -> @html.Html {
  if data.loading {
    return @html.div(
      style=["padding: 20px", "font-family: ui-sans-serif, system-ui"],
      "Loading...",
    )
  }
  let filtered = @core_bench.filter_rows(rows, ui.filter, ui.search)
  let body = []
  for index, row in filtered {
    for
      element in row_view(
        row,
        index,
        ui.expanded.contains(row.key),
        ui_emit,
        log_emit,
      ) {
      body.push(element)
    }
  }
  @html.div(
    style=[
      "min-width: 960px",
      "padding: 18px 20px 26px",
      SANS,
      "color: #111827",
    ],
    [
      header(data.data.current.metadata),
      events_panel(
        data.events,
        match data.data.current.metadata {
          Some(metadata) => metadata.generated_at[0:10].to_owned()
          None => ""
        },
      ),
      @html.div(
        style=[
          "display: flex", "flex-wrap: wrap", "gap: 8px", "align-items: stretch",
          "margin-bottom: 12px",
        ],
        [
          filter_button(
            "Regressions",
            ByState(Regression),
            counts.regression,
            ui.filter,
            ui_emit,
          ),
          filter_button(
            "Errors",
            ByState(Errored),
            counts.error,
            ui.filter,
            ui_emit,
          ),
          filter_button(
            "Missing",
            ByState(Missing),
            counts.missing,
            ui.filter,
            ui_emit,
          ),
          filter_button("New", ByState(New), counts.new_, ui.filter, ui_emit),
          filter_button(
            "Improved",
            ByState(Improvement),
            counts.improvement,
            ui.filter,
            ui_emit,
          ),
          filter_button(
            "Stable",
            ByState(Stable),
            counts.stable,
            ui.filter,
            ui_emit,
          ),
          filter_button("Total", AllRows, counts.all, ui.filter, ui_emit),
          @html.input(
            input_type=Text,
            placeholder="Search package, file, label",
            value=ui.search,
            on_input=ui_emit.map(value => SetSearch(value)),
            style=[
              "margin-left: auto",
              "min-width: 280px",
              BORDER,
              "border-radius: 6px",
              "padding: 7px 9px",
              "align-self: center",
            ],
          ),
        ],
      ),
      @html.div(
        style=["margin-bottom: 8px", "font-size: 12px", "color: #4b5563"],
        "Showing \{filtered.length()} of \{rows.length()} benchmarks",
      ),
      @html.table(
        style=[
          "width: 100%", "border-collapse: collapse", "font-size: 12px", "table-layout: fixed",
          "background: white",
        ],
        [table_head(), @html.tbody(body)],
      ),
    ],
  )
}

///|
fn app() -> @rabbita.Val[@html.Html] {
  let (data, _) = @rabbita.create_state_with_init(
    init=emit => {
      (
        {
          data: @core_bench.DashboardData::empty(),
          events: [],
          loading: true,
          pending_days: 0,
        },
        fetch_text(EVENTS_PATH, emit.map(result => EventsLoaded(result))),
      )
    },
    update=(model, msg, emit) => update_data(model, msg, emit),
  )
  let (ui, ui_emit) = @rabbita.create_state(
    { filter: AllRows, search: "", expanded: @sorted_set.SortedSet::new() },
    update=(model, msg, _) => (update_ui(model, msg), @cmd.none),
  )
  let (_, log_emit) = @rabbita.create_state({ pending: None }, update=(
    model,
    msg,
    emit,
  ) => update_logs(model, msg, emit))
  let rows = data.map(data => @core_bench.build_rows(data.data))
  let counts = rows.map(rows => @core_bench.count_rows(rows))
  @rabbita.Val::view4(data, ui, rows, counts, (data, ui, rows, counts) => {
    view(data, ui, rows, counts, ui_emit, log_emit)
  })
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
