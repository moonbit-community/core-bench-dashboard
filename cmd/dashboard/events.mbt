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
/// Read one note file, or nothing if it is not there.
///
/// A missing file is a valid state; a malformed one is not. `events.json` is
/// derived and can be thrown away, but a note is the only copy of what someone
/// concluded, so a typo must not quietly publish a run with it dropped.
async fn read_note_file(path : String) -> @core_bench.Note? raise {
  let text = @fs.read_file(path).text() catch {
    _ => return None
  }
  Some(@json.from_string(text)) catch {
    error => fail("Could not read \{path}: \{error}")
  }
}

///|
/// Every note in the directory, in a stable order.
///
/// One file per note rather than one array, so the dashboard can link a reader
/// straight at the file for a given step. A missing directory means no notes.
async fn read_notes(dir : String) -> Array[@core_bench.Note] raise {
  let names = @fs.readdir(dir, sort=true) catch {
    _ => return []
  }
  let notes = []
  for name in names {
    if !name.has_suffix(".json") {
      continue
    }
    if read_note_file(join(dir, name)) is Some(note) {
      notes.push(note)
    }
  }
  notes
}

///|
/// Fold today's measurements into the event log.
///
/// Returns the new log along with what opened, what closed, and how many notes
/// found a step, so a run says out loud which regressions appeared, which were
/// fixed, and whether an explanation has gone stale.
pub async fn update_regression_events(
  data_dir : String,
  notes_dir : String,
) -> (Array[@core_bench.RegressionEvent], Int, Int, Int) {
  let existing = read_events(data_dir)
  let data = read_dashboard_data(data_dir)
  let notes = read_notes(notes_dir)
  let (events, noted) = @core_bench.apply_notes(
    @core_bench.update_events(@core_bench.build_rows(data), existing),
    notes,
  )
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
  (events, opened, closed, noted)
}
