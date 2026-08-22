// The dashboard's palette and the style fragments shared between elements.

///|
const MONO : String = "font-family: ui-monospace, SFMono-Regular, Consolas, monospace"

///|
const SANS : String = "font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"

///|
const BORDER : String = "border: 1px solid #d1d5db"

///|
/// Background, foreground, and border for one cell state.
priv struct StateColor {
  background : String
  foreground : String
  border : String
}

///|
fn state_color(state : @core_bench.CellState) -> StateColor {
  match state {
    Regression =>
      { background: "#fee2e2", foreground: "#991b1b", border: "#ef4444" }
    Improvement =>
      { background: "#dcfce7", foreground: "#166534", border: "#22c55e" }
    Stable =>
      { background: "#eef2ff", foreground: "#3730a3", border: "#a5b4fc" }
    New => { background: "#fef3c7", foreground: "#92400e", border: "#f59e0b" }
    Missing =>
      { background: "#e5e7eb", foreground: "#374151", border: "#9ca3af" }
    Errored =>
      { background: "#7f1d1d", foreground: "#ffffff", border: "#7f1d1d" }
  }
}

///|
/// The three-letter tag shown in a state badge.
fn state_label(state : @core_bench.CellState) -> String {
  match state {
    Regression => "REG"
    Improvement => "IMP"
    Stable => "OK"
    New => "NEW"
    Missing => "MISS"
    Errored => "ERR"
  }
}
