// Shared vocabulary for the core benchmark dashboard.
//
// The wire shape of every type here is the published data contract: it is what
// `data.jsonl` and `history/index.json` contain, and what fourteen days of
// already-published history are read back with. Renames exist to keep MoonBit
// naming without moving a single byte of that contract.

///|
/// The single platform this dashboard publishes.
///
/// Retained history is keyed by date alone, so history collected on a different
/// platform must not be carried across a change of this constant. See
/// `docs/operations.md`.
pub const DASHBOARD_OS : String = "darwin-arm64"

///|
/// The repository whose `main` branch is benchmarked.
pub const CORE_REPO : String = "https://github.com/moonbitlang/core"

///|
/// A `moon bench --target` value.
#data.derive(Serialize, Deserialize)
pub(all) enum Backend {
  #data.rename("wasm")
  Wasm
  #data.rename("wasm-gc")
  WasmGc
  #data.rename("js")
  Js
  #data.rename("native")
  Native
} derive(Eq, Hash, Debug)

///|
/// Every backend the dashboard collects, in display order.
pub fn backends() -> Array[Backend] {
  [Wasm, WasmGc, Js, Native]
}

///|
/// The name a backend goes by on the command line and on the wire.
pub fn Backend::name(self : Backend) -> String {
  match self {
    Wasm => "wasm"
    WasmGc => "wasm-gc"
    Js => "js"
    Native => "native"
  }
}

///|
pub fn Backend::parse(value : String) -> Backend? {
  match value {
    "wasm" => Some(Wasm)
    "wasm-gc" => Some(WasmGc)
    "js" => Some(Js)
    "native" => Some(Native)
    _ => None
  }
}

///|
pub impl Show for Backend with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
/// Whether a record carries a timing or an explanation of why it has none.
#data.derive(Serialize, Deserialize)
pub(all) enum RunStatus {
  #data.rename("ok")
  Succeeded
  #data.rename("error")
  Failed
} derive(Eq, Debug)

///|
pub impl Show for RunStatus with fn output(self, logger) {
  logger.write_string(
    match self {
      Succeeded => "ok"
      Failed => "error"
    },
  )
}

///|
/// How one backend's current timing compares with the previous retained day.
///
/// UI-only: never serialized.
pub(all) enum CellState {
  Stable
  Regression
  Improvement
  New
  Missing
  Errored
} derive(Eq, Hash, Debug)

///|
pub impl Show for CellState with fn output(self, logger) {
  logger.write_string(
    match self {
      Stable => "stable"
      Regression => "regression"
      Improvement => "improvement"
      New => "new"
      Missing => "missing"
      Errored => "error"
    },
  )
}

///|
/// The first line of every `data.jsonl`.
#data.derive(Serialize, Deserialize)
pub(all) struct Metadata {
  generated_at : String
  #data.rename("runId")
  run_id : String
  #data.rename("runNumber")
  run_number : String
  os : String
  backends : Array[Backend]
  #data.rename("toolchainVersion")
  toolchain_version : Array[String]
  #data.rename("coreRepo")
  core_repo : String
  #data.rename("coreCommitSha")
  core_commit_sha : String
} derive(Eq, Debug)

///|
/// One benchmark result, or one explanation of a missing result.
///
/// Identity is `backend + package + file + line + block_label + case_name`.
/// Single benchmark blocks use an empty `case_name`; batch blocks produce one
/// record per named timing row.
#data.derive(Serialize, Deserialize)
pub(all) struct Record {
  benchmark_id : String
  backend : Backend
  #data.rename("package")
  pkg : String
  file : String
  line : Int
  block_label : String
  case_name : String
  status : RunStatus
  mean_us : Double?
  stddev_us : Double?
  min_us : Double?
  max_us : Double?
  runs : Int?
  batch_size : Int?
  stdout_path : String?
  stderr_path : String?
  reason : String?
  expanded_command : Array[String]?
} derive(Eq, Debug)

///|
/// A parsed `data.jsonl`: its metadata line and every record line after it.
pub(all) struct Jsonl {
  metadata : Metadata?
  records : Array[Record]
} derive(Eq, Debug)

///|
pub fn Jsonl::empty() -> Jsonl {
  { metadata: None, records: [] }
}

///|
/// One retained calendar day in `history/index.json`.
#data.derive(Serialize, Deserialize)
pub(all) struct HistoryDay {
  date : String
  os : String
  path : String
} derive(Eq, Debug)

///|
#data.derive(Serialize, Deserialize)
pub(all) struct HistoryIndex {
  generated_at : String
  retention_days : Int
  days : Array[HistoryDay]
} derive(Eq, Debug)

///|
/// The fields that make a benchmark the same benchmark across days.
pub(all) struct Identity {
  pkg : String
  file : String
  line : Int
  block_label : String
  case_name : String
} derive(Eq, Debug)
