// Regression events: what is outstanding, and since when.
//
// A cell compares today with the previous retained day, which answers "what
// changed last night" and nothing else. Leave a regression unfixed and the next
// day compares against the regressed value, so the cell goes quiet while the
// benchmark is still slow. An event remembers the value the benchmark broke
// from, and keeps remembering it after that value has aged out of the window.
//
// Opening is derived from the retained series; only the baseline needs storing.
// Lose `events.json` and the next run rebuilds whatever is still visible in the
// last fourteen days.

///|
/// One backend's retained values, oldest first, skipping days with no timing.
priv struct Measured {
  date : String
  value : Double
}

///|
fn measured_series(points : Array[SeriesPoint]) -> Array[Measured] {
  let out = []
  for point in points {
    if point.record is Some(record) &&
      record.status is Succeeded &&
      record.mean_us is Some(value) {
      out.push({ date: point.date, value })
    }
  }
  out
}

///|
/// A step up that has not come back down.
priv struct Step {
  opened_on : String
  baseline_on : String
  baseline_us : Double
}

///|
/// The oldest unrecovered step in a series, if today has confirmed it.
///
/// Walking forward, a value 5% above the running reference opens a step and
/// freezes the reference at the pre-step value; a value back within 5% of that
/// reference closes it again. The step must have happened *before* the last
/// measured day: a jump that appeared today has not survived a night yet, and
/// one night is what separates a regression from a blip.
fn confirmed_step(series : Array[Measured]) -> Step? {
  guard series.length() >= 3 else { return None }
  let mut reference = series[0]
  let mut step : Step? = None
  for index in 1..<series.length() {
    let point = series[index]
    match step {
      None =>
        if point.value >= reference.value * REGRESSION_RATIO {
          step = Some({
            opened_on: point.date,
            baseline_on: reference.date,
            baseline_us: reference.value,
          })
        } else {
          reference = point
        }
      Some(open) =>
        if point.value <= open.baseline_us * REGRESSION_RATIO {
          step = None
          reference = point
        }
    }
  }
  guard step is Some(step) else { return None }
  // Unconfirmed while the step is the most recent measurement.
  guard step.opened_on != series[series.length() - 1].date else { return None }
  Some(step)
}

///|
fn event_from_step(
  row : Row,
  backend : Backend,
  step : Step,
  latest : Measured,
) -> RegressionEvent {
  {
    benchmark_id: "\{backend}|\{row.pkg}|\{row.file}|\{row.line}|\{row.block_label}|\{row.case_name}",
    backend,
    pkg: row.pkg,
    file: row.file,
    line: row.line,
    block_label: row.block_label,
    case_name: row.case_name,
    opened_on: step.opened_on,
    baseline_us: step.baseline_us,
    baseline_on: step.baseline_on,
    latest_us: latest.value,
    latest_on: latest.date,
    note: None,
  }
}

///|
/// Today's measured value for every benchmark and backend.
fn latest_by_benchmark(rows : Array[Row]) -> Map[String, Measured] {
  let latest : Map[String, Measured] = Map([])
  for row in rows {
    for backend in backends() {
      guard row.series.get(backend) is Some(points) else { continue }
      let series = measured_series(points)
      guard series.length() > 0 else { continue }
      let id = "\{backend}|\{row.pkg}|\{row.file}|\{row.line}|\{row.block_label}|\{row.case_name}"
      latest[id] = series[series.length() - 1]
    }
  }
  latest
}

///|
/// Carry events forward: close what recovered, open what has been confirmed.
///
/// An existing event always wins over a freshly detected one, because its
/// baseline may predate everything still in the window. An event whose
/// benchmark has no measurement today is left untouched rather than closed —
/// a benchmark that vanished is not a benchmark that got faster.
pub fn update_events(
  rows : Array[Row],
  existing : Array[RegressionEvent],
) -> Array[RegressionEvent] {
  let latest = latest_by_benchmark(rows)
  let out = []
  let carried = Set([])
  for event in existing {
    match latest.get(event.benchmark_id) {
      None => {
        out.push(event)
        carried.add(event.benchmark_id)
      }
      Some(today) =>
        if today.value <= event.baseline_us * REGRESSION_RATIO {
          // Recovered.
          ()
        } else {
          out.push({ ..event, latest_us: today.value, latest_on: today.date })
          carried.add(event.benchmark_id)
        }
    }
  }
  for row in rows {
    for backend in backends() {
      guard row.series.get(backend) is Some(points) else { continue }
      let series = measured_series(points)
      guard confirmed_step(series) is Some(step) else { continue }
      let event = event_from_step(
        row,
        backend,
        step,
        series[series.length() - 1],
      )
      if !carried.contains(event.benchmark_id) {
        out.push(event)
        carried.add(event.benchmark_id)
      }
    }
  }
  // Oldest first, so what has been outstanding longest reads first. The file is
  // committed on every run, so the order has to be stable.
  out.sort_by((left, right) => {
    let by_date = left.opened_on.lexical_compare(right.opened_on)
    if by_date != 0 {
      return by_date
    }
    left.benchmark_id.lexical_compare(right.benchmark_id)
  })
  out
}

///|
/// How far above its baseline an event currently sits.
pub fn RegressionEvent::delta_percent(self : RegressionEvent) -> Double {
  (self.latest_us / self.baseline_us - 1.0) * 100.0
}

///|
/// The events a panel is showing, narrowed three ways.
///
/// Five percent is what opens an event, and most of what opens sits just above
/// it. Reading the panel means asking for the steps worth chasing, so the
/// threshold is a parameter rather than the opening ratio a second time.
///
/// `noted` is three-state on purpose: `Some(true)` is what has been explained,
/// `Some(false)` is the triage backlog, and `None` is both.
pub fn filter_events(
  events : Array[RegressionEvent],
  backend : Backend?,
  min_percent : Double,
  noted : Bool?,
) -> Array[RegressionEvent] {
  events.filter(event => {
    if backend is Some(backend) && event.backend != backend {
      return false
    }
    if noted is Some(noted) && (event.note is Some(_)) != noted {
      return false
    }
    event.delta_percent() >= min_percent
  })
}

///|
/// Fold human notes onto the events they explain.
///
/// A note is matched on `benchmark_id` and `opened_on` together, so it explains
/// one step rather than one benchmark. `update_events` carries an existing
/// event forward with its original `opened_on`, which is what makes that key
/// stable for as long as the regression is outstanding.
///
/// Returns the annotated events and how many notes found a step. A note that
/// matches nothing is not an error — the event it explained may have closed —
/// but the count makes an orphan visible in a run log.
pub fn apply_notes(
  events : Array[RegressionEvent],
  notes : Array[Note],
) -> (Array[RegressionEvent], Int) {
  let by_key : Map[String, String] = Map([])
  for note in notes {
    by_key["\{note.benchmark_id}|\{note.opened_on}"] = note.text
  }
  let matched : Set[String] = Set([])
  let out = events.map(event => {
    let key = "\{event.benchmark_id}|\{event.opened_on}"
    guard by_key.get(key) is Some(text) else { return event }
    matched.add(key)
    { ..event, note: Some(text) }
  })
  (out, matched.length())
}

///|
/// The file a note about this step lives in.
///
/// Readable in a directory listing and stable for as long as the event is
/// open, which is what lets the dashboard build a link to it without knowing
/// anything the browser cannot see. Not unique by construction — two packages
/// may share a block label — so `dashboard note` refuses to write over a file
/// naming a different benchmark rather than pretending the name is a key.
pub fn RegressionEvent::note_slug(self : RegressionEvent) -> String {
  let source = "\{self.backend} \{self.block_label} \{self.case_name} \{self.opened_on}"
  let out = StringBuilder()
  let mut started = false
  let mut pending_dash = false
  for ch in source.to_lower() {
    if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
      if pending_dash && started {
        out.write_char('-')
      }
      out.write_char(ch)
      started = true
      pending_dash = false
    } else {
      pending_dash = true
    }
  }
  "\{out}.json"
}
