// Opening a benchmark's captured logs as a plain-text document.
//
// The logs live beside the data as static files, so the viewer fetches them on
// demand rather than the page carrying megabytes it will almost never show.

///|
/// A stream that has arrived, whether or not it could be read.
priv enum LogBody {
  Text(String)
  Unavailable
} derive(Eq)

///|
/// A log document being assembled from up to two fetches.
priv struct LogRequest {
  header : String
  stderr_path : String?
  stdout_path : String?
  stderr : LogBody?
  stdout : LogBody?
} derive(Eq)

///|
priv struct LogModel {
  pending : LogRequest?
} derive(Eq)

///|
priv enum LogMsg {
  Open(@core_bench.Record?, String)
  StderrLoaded(Result[String, Error])
  StdoutLoaded(Result[String, Error])
}

///|
/// Everything the dashboard knows about a record, above its captured output.
fn describe(record : @core_bench.Record, label : String) -> String {
  let out = StringBuilder::new()
  out.write_string("\{label}\n")
  out.write_string("benchmark_id: \{record.benchmark_id}\n")
  out.write_string("backend: \{record.backend}\n")
  out.write_string("package: \{record.pkg}\n")
  out.write_string("file: \{record.file}:\{record.line}\n")
  let case_suffix = if record.case_name.is_empty() {
    ""
  } else {
    " / \{record.case_name}"
  }
  out.write_string("label: \{record.block_label}\{case_suffix}\n")
  out.write_string("status: \{record.status}\n")
  if record.expanded_command is Some(command) {
    out.write_string("command: \{command.join(" ")}\n")
  }
  if record.reason is Some(reason) {
    out.write_string("reason: \{reason}\n")
  }
  out.write_string("\n")
  out.to_string()
}

///|
/// One fetched stream, or the reason it could not be read.
fn section(name : String, path : String?, body : LogBody?) -> String {
  guard path is Some(path) else { return "" }
  let text = match body {
    Some(Text(text)) => text
    _ => "Failed to fetch \{path}"
  }
  "\{name}:\n\{text}\n"
}

///|
/// Whether every stream this document waits on has arrived.
fn LogRequest::is_complete(self : LogRequest) -> Bool {
  (self.stderr_path is None || self.stderr is Some(_)) &&
  (self.stdout_path is None || self.stdout is Some(_))
}

///|
fn LogRequest::render(self : LogRequest) -> String {
  let stderr = section("STDERR", self.stderr_path, self.stderr)
  let stdout = section("STDOUT", self.stdout_path, self.stdout)
  let separator = if stderr.is_empty() { "" } else { "\n" }
  "\{self.header}\{stderr}\{separator}\{stdout}"
}

///|
/// Hand a finished document to the viewer, or keep waiting.
fn settle(request : LogRequest) -> (LogModel, @cmd.Cmd) {
  if request.is_complete() {
    (
      { pending: None },
      @cmd.effect(() => open_text_in_new_tab(request.render())),
    )
  } else {
    ({ pending: Some(request) }, @cmd.none)
  }
}

///|
fn update_logs(
  model : LogModel,
  msg : LogMsg,
  emit : @cmd.Emit[LogMsg],
) -> (LogModel, @cmd.Cmd) {
  match msg {
    Open(None, label) =>
      (
        model,
        @cmd.effect(() => open_text_in_new_tab("No \{label} result record.")),
      )
    Open(Some(record), label) => {
      let request : LogRequest = {
        header: describe(record, label),
        stderr_path: record.stderr_path,
        stdout_path: record.stdout_path,
        stderr: None,
        stdout: None,
      }
      let fetches = []
      if record.stderr_path is Some(path) {
        fetches.push(
          @http.get(path).expect_text(emit.map(result => StderrLoaded(result))),
        )
      }
      if record.stdout_path is Some(path) {
        fetches.push(
          @http.get(path).expect_text(emit.map(result => StdoutLoaded(result))),
        )
      }
      let (next, ready) = settle(request)
      (next, @cmd.batch([ready, ..fetches]))
    }
    StderrLoaded(result) => {
      guard model.pending is Some(request) else { return (model, @cmd.none) }
      settle({ ..request, stderr: Some(body_of(result)) })
    }
    StdoutLoaded(result) => {
      guard model.pending is Some(request) else { return (model, @cmd.none) }
      settle({ ..request, stdout: Some(body_of(result)) })
    }
  }
}

///|
/// A failed fetch is still an arrival: the document says so by path.
fn body_of(result : Result[String, Error]) -> LogBody {
  match result {
    Ok(text) => Text(text)
    Err(_) => Unavailable
  }
}
