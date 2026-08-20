export const CORE_REPO = 'https://github.com/moonbitlang/core' as const;
export const DASHBOARD_OS = 'darwin-arm64' as const;
export const CORE_BENCH_BACKENDS = ['wasm', 'wasm-gc', 'js', 'native'] as const;

export type CoreBenchOS = typeof DASHBOARD_OS;
export type CoreBenchBackend = (typeof CORE_BENCH_BACKENDS)[number];
export type CoreBenchStatus = 'ok' | 'error';
export type CoreBenchCellState = 'stable' | 'regression' | 'improvement' | 'new' | 'missing' | 'error';

export interface CoreBenchMetadata {
  generated_at: string;
  runId: string;
  runNumber: string;
  os: CoreBenchOS;
  backends: CoreBenchBackend[];
  toolchainVersion: string[];
  coreRepo: string;
  coreCommitSha: string;
}

export interface CoreBenchRecord {
  benchmark_id: string;
  backend: CoreBenchBackend;
  package: string;
  file: string;
  line: number;
  block_label: string;
  case_name: string;
  status: CoreBenchStatus;
  mean_us?: number;
  stddev_us?: number;
  min_us?: number;
  max_us?: number;
  runs?: number;
  batch_size?: number;
  stdout_path?: string;
  stderr_path?: string;
  reason?: string;
  expanded_command?: string[];
}

export interface CoreBenchJsonl {
  metadata: CoreBenchMetadata | null;
  records: CoreBenchRecord[];
}

export interface HistoryDay {
  date: string;
  os: CoreBenchOS;
  path: string;
}

export interface HistoryIndex {
  generated_at: string;
  retention_days: number;
  days: HistoryDay[];
}

export interface BenchmarkIdentity {
  package: string;
  file: string;
  line: number;
  block_label: string;
  case_name: string;
}
