// Derived trait impls are also promoted to regular methods on the type, which
// would widen this package's surface with an API nobody asked for. Each
// promotion is named here, deprecated and hidden, so the impls stay reachable
// through their trait bounds and warning 79 stays quiet.

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Backend with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Hash` bound", skip_current_package=true)
#doc(hidden)
pub extend Backend with Hash::{hash, hash_combine}

///|
#deprecated("reach it through the `Show` bound, or use `Backend::name`", skip_current_package=true)
#doc(hidden)
pub extend Backend with Show::{output, to_string}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend RunStatus with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Show` bound", skip_current_package=true)
#doc(hidden)
pub extend RunStatus with Show::{output, to_string}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend CellState with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Hash` bound", skip_current_package=true)
#doc(hidden)
pub extend CellState with Hash::{hash, hash_combine}

///|
#deprecated("reach it through the `Show` bound", skip_current_package=true)
#doc(hidden)
pub extend CellState with Show::{output, to_string}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Metadata with Eq::{equal, not_equal}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Record with Eq::{equal, not_equal}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Jsonl with Eq::{equal, not_equal}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend HistoryDay with Eq::{equal, not_equal}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend HistoryIndex with Eq::{equal, not_equal}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Identity with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Backend with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend RunStatus with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend CellState with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Metadata with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Record with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Jsonl with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend HistoryDay with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend HistoryIndex with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Identity with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Filter with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Filter with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend BackendCell with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend BackendCell with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend SeriesPoint with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend SeriesPoint with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Row with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Row with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend HistoryEntry with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend HistoryEntry with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend DashboardData with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend DashboardData with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend RowCounts with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend RowCounts with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend Delta with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend Delta with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend OverallStatus with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend OverallStatus with @debug.Debug::{to_repr}

///|
#deprecated("use `==` and `!=`", skip_current_package=true)
#doc(hidden)
pub extend StatusSummary with Eq::{equal, not_equal}

///|
#deprecated("reach it through the `Debug` bound", skip_current_package=true)
#doc(hidden)
pub extend StatusSummary with @debug.Debug::{to_repr}

///|
#deprecated("reach it through the `Show` bound", skip_current_package=true)
#doc(hidden)
pub extend OverallStatus with Show::{output, to_string}
