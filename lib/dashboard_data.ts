import {
  CORE_BENCH_BACKENDS,
  CoreBenchBackend,
  CoreBenchCellState,
  CoreBenchJsonl,
  CoreBenchRecord,
  HistoryIndex,
} from './types.ts';

export type Filter = 'all' | 'regression' | 'improvement' | 'new' | 'missing' | 'error' | 'stable';

export interface BackendCell {
  backend: CoreBenchBackend;
  current?: CoreBenchRecord;
  previous?: CoreBenchRecord;
  state: CoreBenchCellState;
  deltaRatio?: number;
  deltaPercent?: number;
}

export interface SeriesPoint {
  date: string;
  record?: CoreBenchRecord;
}

export interface DashboardRow {
  key: string;
  package: string;
  file: string;
  line: number;
  block_label: string;
  case_name: string;
  cells: Map<CoreBenchBackend, BackendCell>;
  series: Map<CoreBenchBackend, SeriesPoint[]>;
  state: CoreBenchCellState;
  regressionCount: number;
  improvementCount: number;
  errorCount: number;
  missingCount: number;
  newCount: number;
  stableCount: number;
}

export interface DashboardData {
  current: CoreBenchJsonl;
  history: Array<{ date: string; data: CoreBenchJsonl }>;
  historyIndex: HistoryIndex | null;
}

const STATE_PRIORITY: Record<CoreBenchCellState, number> = {
  error: 0,
  regression: 1,
  missing: 2,
  new: 3,
  improvement: 4,
  stable: 5,
};

export function emptyDashboardData(): DashboardData {
  return {
    current: { metadata: null, records: [] },
    history: [],
    historyIndex: null,
  };
}

export function identityKey(record: Pick<CoreBenchRecord, 'package' | 'file' | 'line' | 'block_label' | 'case_name'>) {
  return [record.package, record.file, String(record.line), record.block_label, record.case_name].join('\0');
}

export function classifyDelta(
  current: Pick<CoreBenchRecord, 'status' | 'mean_us'> | undefined,
  previous: Pick<CoreBenchRecord, 'status' | 'mean_us'> | undefined,
): { state: CoreBenchCellState; deltaRatio?: number; deltaPercent?: number } {
  if (current?.status === 'error') return { state: 'error' };
  if (!current && previous?.status === 'ok') return { state: 'missing' };
  if (!current) return { state: 'missing' };
  if (!previous || previous.status !== 'ok' || previous.mean_us === undefined) return { state: 'new' };
  if (current.mean_us === undefined) return { state: 'new' };

  const deltaRatio = current.mean_us / previous.mean_us;
  const deltaPercent = (deltaRatio - 1) * 100;
  if (deltaRatio >= 1.05) return { state: 'regression', deltaRatio, deltaPercent };
  if (deltaRatio <= 0.95) return { state: 'improvement', deltaRatio, deltaPercent };
  return { state: 'stable', deltaRatio, deltaPercent };
}

function ensureRow(rows: Map<string, DashboardRow>, record: CoreBenchRecord): DashboardRow {
  const key = identityKey(record);
  const existing = rows.get(key);
  if (existing) return existing;
  const row: DashboardRow = {
    key,
    package: record.package,
    file: record.file,
    line: record.line,
    block_label: record.block_label,
    case_name: record.case_name,
    cells: new Map(),
    series: new Map(),
    state: 'missing',
    regressionCount: 0,
    improvementCount: 0,
    errorCount: 0,
    missingCount: 0,
    newCount: 0,
    stableCount: 0,
  };
  rows.set(key, row);
  return row;
}

function latestPreviousDay(data: DashboardData): { date: string; data: CoreBenchJsonl } | undefined {
  const currentDate = data.current.metadata?.generated_at.slice(0, 10);
  const candidates = currentDate ? data.history.filter((day) => day.date < currentDate) : data.history;
  return candidates.toSorted((a, b) => a.date.localeCompare(b.date)).at(-1);
}

export function buildRows(data: DashboardData): DashboardRow[] {
  const rows = new Map<string, DashboardRow>();
  const previous = latestPreviousDay(data);

  for (const record of data.current.records) {
    ensureRow(rows, record);
  }
  for (const record of previous?.data.records ?? []) {
    ensureRow(rows, record);
  }
  for (const day of data.history) {
    for (const record of day.data.records) {
      ensureRow(rows, record);
    }
  }

  const currentByIdentity = new Map<string, Map<CoreBenchBackend, CoreBenchRecord>>();
  for (const record of data.current.records) {
    const byBackend = currentByIdentity.get(identityKey(record)) ?? new Map<CoreBenchBackend, CoreBenchRecord>();
    byBackend.set(record.backend, record);
    currentByIdentity.set(identityKey(record), byBackend);
  }

  const previousByIdentity = new Map<string, Map<CoreBenchBackend, CoreBenchRecord>>();
  for (const record of previous?.data.records ?? []) {
    const byBackend = previousByIdentity.get(identityKey(record)) ?? new Map<CoreBenchBackend, CoreBenchRecord>();
    byBackend.set(record.backend, record);
    previousByIdentity.set(identityKey(record), byBackend);
  }

  for (const row of rows.values()) {
    for (const backend of CORE_BENCH_BACKENDS) {
      const current = currentByIdentity.get(row.key)?.get(backend);
      const previousRecord = previousByIdentity.get(row.key)?.get(backend);
      const delta = classifyDelta(current, previousRecord);
      row.cells.set(backend, {
        backend,
        current,
        previous: previousRecord,
        state: delta.state,
        deltaRatio: delta.deltaRatio,
        deltaPercent: delta.deltaPercent,
      });

      row.series.set(
        backend,
        data.history
          .toSorted((a, b) => a.date.localeCompare(b.date))
          .map((day) => ({
            date: day.date,
            record: day.data.records.find((record) => identityKey(record) === row.key && record.backend === backend),
          })),
      );
    }

    row.regressionCount = countCells(row, 'regression');
    row.improvementCount = countCells(row, 'improvement');
    row.errorCount = countCells(row, 'error');
    row.missingCount = countCells(row, 'missing');
    row.newCount = countCells(row, 'new');
    row.stableCount = countCells(row, 'stable');
    row.state = row.errorCount > 0
      ? 'error'
      : row.regressionCount > 0
      ? 'regression'
      : row.missingCount > 0
      ? 'missing'
      : row.newCount > 0
      ? 'new'
      : row.improvementCount > 0
      ? 'improvement'
      : 'stable';
  }

  return Array.from(rows.values()).sort((left, right) => {
    const priority = STATE_PRIORITY[left.state] - STATE_PRIORITY[right.state];
    if (priority !== 0) return priority;
    return left.package.localeCompare(right.package) ||
      left.file.localeCompare(right.file) ||
      left.line - right.line ||
      left.block_label.localeCompare(right.block_label) ||
      left.case_name.localeCompare(right.case_name);
  });
}

function countCells(row: DashboardRow, state: CoreBenchCellState): number {
  return Array.from(row.cells.values()).filter((cell) => cell.state === state).length;
}

export function filterRows(rows: DashboardRow[], filter: Filter, search: string): DashboardRow[] {
  const keyword = search.trim().toLowerCase();
  return rows.filter((row) => {
    if (
      filter !== 'all' && row.state !== filter && !Array.from(row.cells.values()).some((cell) => cell.state === filter)
    ) {
      return false;
    }
    if (!keyword) return true;
    return `${row.package} ${row.file} ${row.line} ${row.block_label} ${row.case_name}`.toLowerCase().includes(keyword);
  });
}

export function countRows(rows: DashboardRow[]): Record<Filter, number> {
  return {
    all: rows.length,
    regression: rows.filter((row) => row.regressionCount > 0).length,
    improvement: rows.filter((row) => row.improvementCount > 0).length,
    new: rows.filter((row) => row.newCount > 0).length,
    missing: rows.filter((row) => row.missingCount > 0).length,
    error: rows.filter((row) => row.errorCount > 0).length,
    stable: rows.filter((row) => row.state === 'stable').length,
  };
}

export function hasCurrentRegressionOrError(data: DashboardData): boolean {
  return buildRows(data).some((row) =>
    Array.from(row.cells.values()).some((cell) => cell.state === 'regression' || cell.state === 'error')
  );
}
