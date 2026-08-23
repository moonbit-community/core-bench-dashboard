// Reading and rewriting the regression event log.

///|
fn events_path(data_dir : String) -> String {
  join(data_dir, "events.json")
}

///|
/// Read the event log, treating a missing file as no open events.
async fn read_events(data_dir : String) -> Array[@core_bench.RegressionEvent] {
  let text = @fs.read_file(events_path(data_dir)).text() catch {
    _ => return []
  }
  @json.from_string(text) catch {
    _ => []
  }
}

///|
/// Fold today's measurements into the event log.
///
/// Returns the new log along with what opened and what closed, so a run says
/// out loud which regressions appeared and which were fixed.
pub async fn update_regression_events(
  data_dir : String,
) -> (Array[@core_bench.RegressionEvent], Int, Int) {
  let existing = read_events(data_dir)
  let data = read_dashboard_data(data_dir)
  let events = @core_bench.update_events(@core_bench.build_rows(data), existing)
  let before = Set([])
  for event in existing {
    before.add(event.benchmark_id)
  }
  let after = Set([])
  for event in events {
    after.add(event.benchmark_id)
  }
  let opened = events
    .filter(event => !before.contains(event.benchmark_id))
    .length()
  let closed = existing
    .filter(event => !after.contains(event.benchmark_id))
    .length()
  write_file(events_path(data_dir), pretty_json(@json.to_string(events)))
  (events, opened, closed)
}
