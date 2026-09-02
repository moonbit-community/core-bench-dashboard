// The three things a browser does that MoonBit has no portable answer for:
// fixed-point number formatting, local-time formatting, and handing the viewer
// a text document. Everything else in this package is ordinary MoonBit.

///|
/// `Number.prototype.toFixed`, so timings render exactly as they always have.
extern "js" fn to_fixed(value : Double, digits : Int) -> String =
  #|(value, digits) => value.toFixed(digits)

///|
/// Format an ISO timestamp in the viewer's own time zone.
///
/// An unparseable value is shown as-is rather than as an error.
extern "js" fn format_local(value : String) -> String =
  #|(value) => {
  #|  const date = new Date(value);
  #|  if (Number.isNaN(date.getTime())) return value;
  #|  const pad = (n) => String(n).padStart(2, "0");
  #|  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  #|    + ` ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  #|}

///|
/// The directory this page was served from.
extern "js" fn document_base() -> String =
  #|() => new URL(".", document.baseURI).href

///|
/// Resolve a published data path against the page's own directory.
///
/// `@http.get` resolves a relative path against the origin rather than the
/// document, so under a project Pages site — served from `/<repo>/` — every
/// data request drops that segment and 404s. Serving the dashboard from a
/// server root hides this completely, which is how it reached production.
fn site_url(path : String) -> String {
  if path.contains("://") {
    path
  } else {
    "\{document_base()}\{path}"
  }
}

///|
/// Open a plain-text document in a new tab.
extern "js" fn open_text_in_new_tab(content : String) -> Unit =
  #|(content) => {
  #|  const blob = new Blob([content], { type: "text/plain;charset=utf8" });
  #|  const url = URL.createObjectURL(blob);
  #|  const tab = window.open(url, "_blank");
  #|  if (tab) setTimeout(() => URL.revokeObjectURL(url), 1000);
  #|}

///|
/// `encodeURIComponent`, for the query of a GitHub prefill link.
extern "js" fn encode_uri_component(value : String) -> String =
  #|(value) => encodeURIComponent(value)

///|
/// Today's calendar date, in the reader's own time zone.
///
/// A note records when a person wrote it, which is their today rather than the
/// benchmark run's.
extern "js" fn today_local() -> String =
  #|() => {
  #|  const now = new Date();
  #|  const pad = (n) => String(n).padStart(2, "0");
  #|  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  #|}
