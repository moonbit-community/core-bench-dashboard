// The event state machine, exercised on synthetic series.
//
// Each test builds a benchmark's history day by day, so the intent is readable
// as a timeline rather than as a fixture.

///|
fn series_data(values : Array[Double?]) -> @core_bench.DashboardData {
  let history = []
  for index, value in values {
    let day = "2026-05-\{if index + 1 < 10 { "0" } else { "" }}\{index + 1}"
    let records = match value {
      Some(value) => [test_record("bench", Wasm, value)]
      None => []
    }
    history.push(
      (
        { date: day, data: { metadata: Some(test_metadata(day)), records } } :
        @core_bench.HistoryEntry),
    )
  }
  let last = values.length()
  {
    current: {
      metadata: Some(
        test_metadata("2026-05-\{if last < 10 { "0" } else { "" }}\{last}"),
      ),
      records: [],
    },
    history,
    history_index: None,
  }
}

///|
fn events_for(values : Array[Double?]) -> Array[@core_bench.RegressionEvent] {
  @core_bench.update_events(@core_bench.build_rows(series_data(values)), [])
}

///|
test "a step that survives a night opens an event" {
  let events = events_for([Some(100.0), Some(100.0), Some(106.0), Some(107.0)])
  assert_eq(events.length(), 1)
  assert_eq(events[0].opened_on, "2026-05-03")
  assert_eq(events[0].baseline_us, 100.0)
  assert_eq(events[0].baseline_on, "2026-05-02")
  assert_eq(events[0].latest_us, 107.0)
  assert_eq(events[0].latest_on, "2026-05-04")
  assert_true((events[0].delta_percent() - 7.0).abs() < 1.0e-9)
}

///|
test "a step measured only today is not yet confirmed" {
  assert_eq(events_for([Some(100.0), Some(100.0), Some(106.0)]).length(), 0)
}

///|
test "a one-day blip opens nothing" {
  assert_eq(
    events_for([Some(100.0), Some(106.0), Some(100.0), Some(100.0)]).length(),
    0,
  )
}

///|
test "drift below the threshold opens nothing" {
  assert_eq(
    events_for([Some(100.0), Some(103.0), Some(106.0), Some(109.0)]).length(),
    0,
  )
}

///|
test "a recovered benchmark closes its event" {
  let open = events_for([Some(100.0), Some(100.0), Some(106.0), Some(107.0)])
  assert_eq(open.length(), 1)
  let recovered = @core_bench.update_events(
    @core_bench.build_rows(
      series_data([
        Some(100.0),
        Some(100.0),
        Some(106.0),
        Some(107.0),
        Some(101.0),
      ]),
    ),
    open,
  )
  assert_eq(recovered.length(), 0)
}

///|
test "an event outlives its baseline ageing out of the window" {
  // The window now holds only regressed values: nothing in it could rebuild
  // the event, and the stored baseline is the only memory of the old number.
  let open = events_for([Some(100.0), Some(100.0), Some(106.0), Some(107.0)])
  let carried = @core_bench.update_events(
    @core_bench.build_rows(series_data([Some(107.0), Some(107.0), Some(108.0)])),
    open,
  )
  assert_eq(carried.length(), 1)
  assert_eq(carried[0].baseline_us, 100.0)
  assert_eq(carried[0].opened_on, "2026-05-03")
  assert_eq(carried[0].latest_us, 108.0)
  assert_eq(carried[0].latest_on, "2026-05-03")
}

///|
test "rerunning the same day changes nothing" {
  let values = [Some(100.0), Some(100.0), Some(106.0), Some(107.0)]
  let once = events_for(values)
  let twice = @core_bench.update_events(
    @core_bench.build_rows(series_data(values)),
    once,
  )
  assert_eq(once, twice)
}

///|
test "a missing day does not break the walk" {
  let events = events_for([Some(100.0), None, Some(106.0), Some(107.0)])
  assert_eq(events.length(), 1)
  assert_eq(events[0].baseline_us, 100.0)
  assert_eq(events[0].baseline_on, "2026-05-01")
}

///|
test "a benchmark with no measurement today keeps its event" {
  let open = events_for([Some(100.0), Some(100.0), Some(106.0), Some(107.0)])
  let carried = @core_bench.update_events(
    @core_bench.build_rows(
      series_data([Some(100.0), Some(100.0), Some(106.0), Some(107.0), None]),
    ),
    open,
  )
  assert_eq(carried.length(), 1)
  assert_eq(carried[0].latest_on, "2026-05-04")
}

///|
test "too little history opens nothing" {
  assert_eq(events_for([Some(100.0), Some(107.0)]).length(), 0)
}
