import { assertEquals } from './assert.ts';
import { buildRows, classifyDelta, countRows, emptyDashboardData, filterRows } from './dashboard_data.ts';
import type { CoreBenchBackend, CoreBenchMetadata, CoreBenchRecord } from './types.ts';

function metadata(date: string): CoreBenchMetadata {
  return {
    generated_at: `${date}T00:00:00.000Z`,
    runId: '1',
    runNumber: '1',
    os: 'linux-x64',
    backends: ['wasm', 'wasm-gc', 'js', 'native'],
    toolchainVersion: ['moon test'],
    coreRepo: 'https://github.com/moonbitlang/core',
    coreCommitSha: 'a'.repeat(40),
  };
}

function record(
  label: string,
  backend: CoreBenchBackend,
  mean: number,
  status: CoreBenchRecord['status'] = 'ok',
): CoreBenchRecord {
  return {
    benchmark_id: `${backend}|pkg|file.mbt|1|${label}|`,
    backend,
    package: 'moonbitlang/core/pkg',
    file: 'pkg/file.mbt',
    line: 1,
    block_label: label,
    case_name: '',
    status,
    mean_us: status === 'ok' ? mean : undefined,
  };
}

Deno.test('classifyDelta marks 5% threshold boundaries', () => {
  assertEquals(classifyDelta(record('x', 'wasm', 105), record('x', 'wasm', 100)).state, 'regression');
  assertEquals(classifyDelta(record('x', 'wasm', 95), record('x', 'wasm', 100)).state, 'improvement');
  assertEquals(classifyDelta(record('x', 'wasm', 104.99), record('x', 'wasm', 100)).state, 'stable');
  assertEquals(classifyDelta(record('x', 'wasm', 95.01), record('x', 'wasm', 100)).state, 'stable');
  assertEquals(classifyDelta(record('x', 'wasm', 0, 'error'), record('x', 'wasm', 100)).state, 'error');
  assertEquals(classifyDelta(record('x', 'wasm', 100), undefined).state, 'new');
  assertEquals(classifyDelta(undefined, record('x', 'wasm', 100)).state, 'missing');
});

Deno.test('buildRows creates new, missing, error, regression, improvement, and stable cells', () => {
  const data = emptyDashboardData();
  data.current.metadata = metadata('2026-05-24');
  data.history = [{
    date: '2026-05-23',
    data: {
      metadata: metadata('2026-05-23'),
      records: [
        record('stable', 'wasm', 100),
        record('regression', 'wasm', 100),
        record('improvement', 'wasm', 100),
        record('missing', 'wasm', 100),
      ],
    },
  }];
  data.current.records = [
    record('stable', 'wasm', 103),
    record('regression', 'wasm', 106),
    record('improvement', 'wasm', 90),
    record('new', 'wasm', 50),
    record('error', 'wasm', 0, 'error'),
  ];

  const rows = buildRows(data);
  const byLabel = new Map(rows.map((row) => [row.block_label, row]));
  assertEquals(byLabel.get('stable')?.cells.get('wasm')?.state, 'stable');
  assertEquals(byLabel.get('regression')?.cells.get('wasm')?.state, 'regression');
  assertEquals(byLabel.get('improvement')?.cells.get('wasm')?.state, 'improvement');
  assertEquals(byLabel.get('new')?.cells.get('wasm')?.state, 'new');
  assertEquals(byLabel.get('missing')?.cells.get('wasm')?.state, 'missing');
  assertEquals(byLabel.get('error')?.cells.get('wasm')?.state, 'error');
  assertEquals(countRows(rows).regression, 1);
  assertEquals(countRows(rows).improvement, 1);
  assertEquals(countRows(rows).new, 1);
  assertEquals(countRows(rows).missing, 6);
  assertEquals(countRows(rows).error, 1);
  assertEquals(filterRows(rows, 'regression', '').map((row) => row.block_label), ['regression']);
  assertEquals(filterRows(rows, 'all', 'improvement').map((row) => row.block_label), ['improvement']);
});
