// Recording what a human concluded about an outstanding regression.
//
// The note file is the only part of the published data a person writes by
// hand, and a benchmark id is sixty characters of pipe-separated identity that
// nothing in the UI shows. So a note is entered by naming the benchmark the way
// a reader would — a fragment of its label — and the id, the step it belongs to
// and the date are filled in from the event log. A mistyped id would match
// nothing and fail silently; a mistyped fragment fails here, loudly.

///|
/// Where notes live: the repository, not the benchmark archive.
///
/// The archive branch is force-pushed on every run and `docs/operations.md`
/// documents deliberately deleting it. A note is a human judgement that has to
/// survive that, and that deserves a reviewable commit.
///
/// One file per note rather than one array, so a reader can be linked straight
/// at the file for a step. That link is what lets a note be written from the
/// dashboard without the site needing a server to write through.
const DEFAULT_NOTES_DIR : String = "notes"

///|
/// The text a reader would recognize a benchmark by.
fn note_haystack(event : @core_bench.RegressionEvent) -> String {
  "\{event.pkg} \{event.file} \{event.block_label} \{event.case_name}".to_lower()
}

///|
/// The one outstanding regression a backend and a label fragment name.
///
/// Ambiguity is an error rather than a first match: the same label usually
/// exists on all four backends, and silently annotating the wrong one is worse
/// than being asked to narrow the search.
fn resolve_event(
  events : Array[@core_bench.RegressionEvent],
  backend : @core_bench.Backend?,
  keyword : String,
) -> @core_bench.RegressionEvent raise {
  let keyword = keyword.trim().to_lower()
  guard !keyword.is_empty() else { fail("--match cannot be empty.") }
  let found = events.filter(event => {
    if backend is Some(backend) && event.backend != backend {
      return false
    }
    note_haystack(event).contains(keyword)
  })
  match found.length() {
    0 => fail("No outstanding regression matches: \{keyword}")
    1 => found[0]
    _ => {
      let listed = found
        .map(event => "  \{event.backend} \{event.block_label}")
        .join("\n")
      fail(
        "\{found.length()} outstanding regressions match: \{keyword}\n\{listed}\n" +
        "Narrow --match, or pass --backend.",
      )
    }
  }
}

///|
/// Record a note against the step a benchmark is currently broken on.
///
/// Writing twice about the same step replaces the earlier text rather than
/// appending: the file is a set of conclusions, not a log of them.
async fn write_note(
  data_dir : String,
  notes_dir : String,
  backend : @core_bench.Backend?,
  keyword : String,
  text : String,
) -> String raise {
  let text = text.trim().to_owned()
  guard !text.is_empty() else { fail("--text cannot be empty.") }
  let event = resolve_event(read_events(data_dir), backend, keyword)
  let path = join(notes_dir, event.note_slug())
  // The slug is readable rather than unique — two packages may share a block
  // label — so refuse the write instead of silently replacing a note about a
  // different benchmark.
  if read_note_file(path) is Some(existing) &&
    existing.benchmark_id != event.benchmark_id {
    fail("\{path} already holds a note about \{existing.benchmark_id}.")
  }
  let note : @core_bench.Note = {
    benchmark_id: event.benchmark_id,
    opened_on: event.opened_on,
    text,
    noted_on: today_utc(),
  }
  write_file(path, pretty_json(@json.to_string(note)))
  path
}
