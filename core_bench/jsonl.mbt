// Newline-delimited JSON: the first line is metadata, every line after it is
// one benchmark record.

///|
/// Split a document into its non-empty lines, tolerating CRLF.
fn lines(text : String) -> Array[String] {
  let out = []
  for line in text.split("\n") {
    let line = line.trim_end(chars="\r")
    if line.trim(chars=" \t").length() > 0 {
      out.push(line.to_owned())
    }
  }
  out
}

///|
/// Parse a `data.jsonl` document.
///
/// A document with no lines at all is empty rather than an error, which is how
/// a missing current day reads.
pub fn parse_jsonl(text : String) -> Jsonl raise {
  let lines = lines(text)
  if lines.is_empty() {
    return Jsonl::empty()
  }
  let metadata : Metadata = @json.from_string(lines[0])
  let records = []
  for index in 1..<lines.length() {
    records.push((@json.from_string(lines[index]) : Record))
  }
  { metadata: Some(metadata), records }
}

///|
/// Render metadata and records as a `data.jsonl` document.
pub fn stringify_jsonl(
  metadata : Metadata,
  records : Array[Record],
) -> String raise {
  let out = StringBuilder::new()
  out.write_string(@json.to_string(metadata))
  out.write_char('\n')
  for record in records {
    out.write_string(@json.to_string(record))
    out.write_char('\n')
  }
  out.to_string()
}
