///|
fn test_metadata(date : String) -> @core_bench.Metadata {
  {
    generated_at: "\{date}T00:00:00.000Z",
    run_id: "1",
    run_number: "1",
    os: @core_bench.DASHBOARD_OS,
    backends: @core_bench.backends(),
    toolchain_version: ["moon test"],
    core_repo: @core_bench.CORE_REPO,
    core_commit_sha: "a".repeat(40),
  }
}

///|
fn test_record(
  label : String,
  backend : @core_bench.Backend,
  mean : Double,
  status? : @core_bench.RunStatus = Succeeded,
) -> @core_bench.Record {
  {
    benchmark_id: "\{backend}|pkg|file.mbt|1|\{label}|",
    backend,
    pkg: "moonbitlang/core/pkg",
    file: "pkg/file.mbt",
    line: 1,
    block_label: label,
    case_name: "",
    status,
    mean_us: if status is Succeeded {
      Some(mean)
    } else {
      None
    },
    stddev_us: None,
    min_us: None,
    max_us: None,
    runs: None,
    batch_size: None,
    stdout_path: None,
    stderr_path: None,
    reason: None,
    expanded_command: None,
  }
}

///|
test "classify_delta marks the five percent threshold boundaries" {
  fn state(current : Double, previous : Double) {
    @core_bench.classify_delta(
      Some(test_record("x", Wasm, current)),
      Some(test_record("x", Wasm, previous)),
    ).state
  }

  assert_eq(state(105.0, 100.0), Regression)
  assert_eq(state(95.0, 100.0), Improvement)
  assert_eq(state(104.99, 100.0), Stable)
  assert_eq(state(95.01, 100.0), Stable)
  assert_eq(
    @core_bench.classify_delta(
      Some(test_record("x", Wasm, 0.0, status=Failed)),
      Some(test_record("x", Wasm, 100.0)),
    ).state,
    Errored,
  )
  assert_eq(
    @core_bench.classify_delta(Some(test_record("x", Wasm, 100.0)), None).state,
    New,
  )
  assert_eq(
    @core_bench.classify_delta(None, Some(test_record("x", Wasm, 100.0))).state,
    Missing,
  )
}

///|
test "build_rows creates new, missing, error, regression, improvement, and stable cells" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(test_metadata("2026-05-24")),
      records: [
        test_record("stable", Wasm, 103.0),
        test_record("regression", Wasm, 106.0),
        test_record("improvement", Wasm, 90.0),
        test_record("new", Wasm, 50.0),
        test_record("error", Wasm, 0.0, status=Failed),
      ],
    },
    history: [
      {
        date: "2026-05-23",
        data: {
          metadata: Some(test_metadata("2026-05-23")),
          records: [
            test_record("stable", Wasm, 100.0),
            test_record("regression", Wasm, 100.0),
            test_record("improvement", Wasm, 100.0),
            test_record("missing", Wasm, 100.0),
          ],
        },
      },
    ],
    history_index: None,
  }
  let rows = @core_bench.build_rows(data)
  let by_label : Map[String, @core_bench.Row] = Map([])
  for row in rows {
    by_label[row.block_label] = row
  }

  fn wasm_state(label : String) {
    by_label.get(label).bind(row => row.cells.get(Wasm)).map(cell => cell.state)
  }

  assert_eq(wasm_state("stable"), Some(Stable))
  assert_eq(wasm_state("regression"), Some(Regression))
  assert_eq(wasm_state("improvement"), Some(Improvement))
  assert_eq(wasm_state("new"), Some(New))
  assert_eq(wasm_state("missing"), Some(Missing))
  assert_eq(wasm_state("error"), Some(Errored))
  let counts = @core_bench.count_rows(rows)
  assert_eq(counts.regression, 1)
  assert_eq(counts.improvement, 1)
  assert_eq(counts.new_, 1)
  assert_eq(counts.missing, 6)
  assert_eq(counts.error, 1)
  assert_eq(counts.all, 6)
  assert_eq(
    @core_bench.filter_rows(rows, ByState(Regression), "").map(row => {
      row.block_label
    }),
    ["regression"],
  )
  assert_eq(
    @core_bench.filter_rows(rows, AllRows, "improvement").map(row => {
      row.block_label
    }),
    ["improvement"],
  )
}

///|
test "rows sort worst state first" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(test_metadata("2026-05-24")),
      records: [
        test_record("b_stable", Wasm, 100.0),
        test_record("a_error", Wasm, 0.0, status=Failed),
      ],
    },
    history: [
      {
        date: "2026-05-23",
        data: {
          metadata: Some(test_metadata("2026-05-23")),
          records: [test_record("b_stable", Wasm, 100.0)],
        },
      },
    ],
    history_index: None,
  }
  assert_eq(@core_bench.build_rows(data).map(row => row.block_label), [
    "a_error", "b_stable",
  ])
}

///|
test "the series carries every retained day in date order" {
  let data : @core_bench.DashboardData = {
    current: {
      metadata: Some(test_metadata("2026-05-24")),
      records: [test_record("bench", Wasm, 100.0)],
    },
    history: [
      {
        date: "2026-05-23",
        data: {
          metadata: Some(test_metadata("2026-05-23")),
          records: [test_record("bench", Wasm, 90.0)],
        },
      },
      {
        date: "2026-05-21",
        data: { metadata: Some(test_metadata("2026-05-21")), records: [] },
      },
    ],
    history_index: None,
  }
  let row = @core_bench.build_rows(data)[0]
  let series = row.series.get(Wasm).unwrap()
  assert_eq(series.map(point => point.date), ["2026-05-21", "2026-05-23"])
  assert_eq(series[0].record, None)
  assert_eq(series[1].record.map(record => record.mean_us), Some(Some(90.0)))
}
