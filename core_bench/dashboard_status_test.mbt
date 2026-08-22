///|
fn status_metadata(date : String) -> @core_bench.Metadata {
  { ..test_metadata(date), backends: [Wasm], toolchain_version: [] }
}

///|
fn status_record(
  mean : Double,
  status? : @core_bench.RunStatus = Succeeded,
) -> @core_bench.Record {
  {
    ..test_record("bench", Wasm, mean, status~),
    benchmark_id: "wasm|pkg|file.mbt|1|bench|",
  }
}

///|
fn day(date : String, mean : Double) -> @core_bench.HistoryEntry {
  {
    date,
    data: {
      metadata: Some(status_metadata(date)),
      records: [status_record(mean)],
    },
  }
}

///|
test "the badge is green when the current day has no regression or error" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(status_metadata("2026-05-24")),
      records: [status_record(100.0)],
    },
    history: [day("2026-05-23", 98.0)],
    history_index: None,
  }
  let summary = @core_bench.summarize_dashboard_status(data)
  assert_eq(summary.ok, true)
  assert_eq(summary.status, Passing)
  assert_true(
    @core_bench.render_dashboard_status_svg(summary).contains("#2ea44f"),
  )
}

///|
test "the badge is red for a current regression" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(status_metadata("2026-05-24")),
      records: [status_record(106.0)],
    },
    history: [day("2026-05-23", 100.0)],
    history_index: None,
  }
  assert_eq(@core_bench.summarize_dashboard_status(data).status, Failing)
}

///|
test "the badge is red for a failed benchmark command" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(status_metadata("2026-05-24")),
      records: [status_record(0.0, status=Failed)],
    },
    history: [],
    history_index: None,
  }
  let summary = @core_bench.summarize_dashboard_status(data)
  assert_eq(summary.status, Failing)
  assert_true(
    @core_bench.render_dashboard_status_svg(summary).contains("#d73a49"),
  )
}

///|
test "a dashboard with no rows at all is red" {
  let summary = @core_bench.summarize_dashboard_status(
    @core_bench.DashboardData::empty(),
  )
  assert_eq(summary.status, Failing)
  assert_eq(summary.row_count, 0)
}

///|
test "the published badge keeps its bytes" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(status_metadata("2026-05-24")),
      records: [status_record(100.0)],
    },
    history: [day("2026-05-23", 98.0)],
    history_index: None,
  }
  inspect(
    @core_bench.render_dashboard_status_svg(
      @core_bench.summarize_dashboard_status(data),
    ),
    content=(
      #|<svg xmlns="http://www.w3.org/2000/svg" width="136" height="20" role="img" aria-label="core bench: passing">
      #|  <title>core bench: passing (0 regressions, 0 errors)</title>
      #|  <linearGradient id="s" x2="0" y2="100%">
      #|    <stop offset="0" stop-color="#ffffff" stop-opacity=".12"/>
      #|    <stop offset="1" stop-opacity=".12"/>
      #|  </linearGradient>
      #|  <clipPath id="r">
      #|    <rect width="136" height="20" rx="3" fill="#ffffff"/>
      #|  </clipPath>
      #|  <g clip-path="url(#r)">
      #|    <rect width="78" height="20" fill="#555555"/>
      #|    <rect x="78" width="58" height="20" fill="#2ea44f"/>
      #|    <rect width="136" height="20" fill="url(#s)"/>
      #|  </g>
      #|  <g fill="#ffffff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
      #|    <text x="39" y="15" fill="#010101" fill-opacity=".3">core bench</text>
      #|    <text x="39" y="14">core bench</text>
      #|    <text x="107" y="15" fill="#010101" fill-opacity=".3">passing</text>
      #|    <text x="107" y="14">passing</text>
      #|  </g>
      #|</svg>
      #|
    ),
  )
}
