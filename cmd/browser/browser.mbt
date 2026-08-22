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
/// Open a plain-text document in a new tab.
extern "js" fn open_text_in_new_tab(content : String) -> Unit =
  #|(content) => {
  #|  const blob = new Blob([content], { type: "text/plain;charset=utf8" });
  #|  const url = URL.createObjectURL(blob);
  #|  const tab = window.open(url, "_blank");
  #|  if (tab) setTimeout(() => URL.revokeObjectURL(url), 1000);
  #|}
