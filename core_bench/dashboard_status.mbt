// The status badge published at `data/core-bench/status.svg`.
//
// Red when the current day carries a five percent regression or a backend whose
// benchmark command failed; green otherwise. A dashboard with no rows at all is
// red too: nothing measured is not the same as nothing wrong.

///|
const PASS_COLOR : String = "#2ea44f"

///|
const FAIL_COLOR : String = "#d73a49"

///|
const LABEL_COLOR : String = "#555555"

///|
pub(all) enum OverallStatus {
  Passing
  Failing
} derive(Eq, Debug)

///|
pub impl Show for OverallStatus with fn output(self, logger) {
  logger.write_string(
    match self {
      Passing => "passing"
      Failing => "failing"
    },
  )
}

///|
pub(all) struct StatusSummary {
  status : OverallStatus
  ok : Bool
  label : String
  message : String
  color : String
  row_count : Int
  regression_count : Int
  error_count : Int
} derive(Eq, Debug)

///|
/// Reduce a whole dashboard to one green-or-red verdict.
pub fn summarize_dashboard_status(data : DashboardData) -> StatusSummary {
  let rows = build_rows(data)
  let regression_count = rows.fold(init=0, (sum, row) => {
    sum + row.regression_count
  })
  let error_count = rows.fold(init=0, (sum, row) => sum + row.error_count)
  let ok = rows.length() > 0 && regression_count == 0 && error_count == 0
  {
    status: if ok {
      Passing
    } else {
      Failing
    },
    ok,
    label: "core bench",
    message: if ok {
      "passing"
    } else {
      "failing"
    },
    color: if ok {
      PASS_COLOR
    } else {
      FAIL_COLOR
    },
    row_count: rows.length(),
    regression_count,
    error_count,
  }
}

///|
fn escape_xml(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
}

///|
fn badge_text_width(value : String) -> Int {
  let measured = (value.length().to_double() * 6.8 + 10.0).ceil().to_int()
  if measured > 44 {
    measured
  } else {
    44
  }
}

///|
/// Render half of an integer the way a JSON number would print it.
fn half(value : Int) -> String {
  if value % 2 == 0 {
    (value / 2).to_string()
  } else {
    "\{value / 2}.5"
  }
}

///|
/// Render the badge.
pub fn render_dashboard_status_svg(summary : StatusSummary) -> String {
  let label_width = badge_text_width(summary.label)
  let message_width = badge_text_width(summary.message)
  let width = label_width + message_width
  let title = "\{summary.label}: \{summary.message}"
  let detail = "\{summary.regression_count} regressions, \{summary.error_count} errors"
  let label = escape_xml(summary.label)
  let message = escape_xml(summary.message)
  let label_center = half(label_width)
  let message_center = "\{label_width + message_width / 2}"
  (
    $|<svg xmlns="http://www.w3.org/2000/svg" width="\{width}" height="20" role="img" aria-label="\{escape_xml(title)}">
    $|  <title>\{escape_xml("\{title} (\{detail})")}</title>
    $|  <linearGradient id="s" x2="0" y2="100%">
    $|    <stop offset="0" stop-color="#ffffff" stop-opacity=".12"/>
    $|    <stop offset="1" stop-opacity=".12"/>
    $|  </linearGradient>
    $|  <clipPath id="r">
    $|    <rect width="\{width}" height="20" rx="3" fill="#ffffff"/>
    $|  </clipPath>
    $|  <g clip-path="url(#r)">
    $|    <rect width="\{label_width}" height="20" fill="\{LABEL_COLOR}"/>
    $|    <rect x="\{label_width}" width="\{message_width}" height="20" fill="\{summary.color}"/>
    $|    <rect width="\{width}" height="20" fill="url(#s)"/>
    $|  </g>
    $|  <g fill="#ffffff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    $|    <text x="\{label_center}" y="15" fill="#010101" fill-opacity=".3">\{label}</text>
    $|    <text x="\{label_center}" y="14">\{label}</text>
    $|    <text x="\{message_center}" y="15" fill="#010101" fill-opacity=".3">\{message}</text>
    $|    <text x="\{message_center}" y="14">\{message}</text>
    $|  </g>
    $|</svg>
    $|
  )
}
