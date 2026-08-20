import { assertEquals, assertIncludes } from './assert.ts';
import { emptyDashboardData } from './dashboard_data.ts';
import { renderDashboardStatusSvg, summarizeDashboardStatus } from './dashboard_status.ts';
import { type CoreBenchMetadata, type CoreBenchRecord, DASHBOARD_OS } from './types.ts';

function metadata(date: string): CoreBenchMetadata {
  return {
    generated_at: `${date}T00:00:00.000Z`,
    runId: '1',
    runNumber: '1',
    os: DASHBOARD_OS,
    backends: ['wasm'],
    toolchainVersion: [],
    coreRepo: 'https://github.com/moonbitlang/core',
    coreCommitSha: 'a'.repeat(40),
  };
}

function record(mean: number, status: CoreBenchRecord['status'] = 'ok'): CoreBenchRecord {
  return {
    benchmark_id: 'wasm|pkg|file.mbt|1|bench|',
    backend: 'wasm',
    package: 'moonbitlang/core/pkg',
    file: 'pkg/file.mbt',
    line: 1,
    block_label: 'bench',
    case_name: '',
    status,
    mean_us: status === 'ok' ? mean : undefined,
  };
}

Deno.test('summarizeDashboardStatus is green when current data has no regression or error', () => {
  const data = emptyDashboardData();
  data.current = { metadata: metadata('2026-05-24'), records: [record(100)] };
  data.history = [{ date: '2026-05-23', data: { metadata: metadata('2026-05-23'), records: [record(98)] } }];
  const summary = summarizeDashboardStatus(data);
  assertEquals(summary.ok, true);
  assertEquals(summary.status, 'passing');
  assertIncludes(renderDashboardStatusSvg(summary), '#2ea44f');
});

Deno.test('summarizeDashboardStatus is red for current regression or command error', () => {
  const regressed = emptyDashboardData();
  regressed.current = { metadata: metadata('2026-05-24'), records: [record(106)] };
  regressed.history = [{ date: '2026-05-23', data: { metadata: metadata('2026-05-23'), records: [record(100)] } }];
  assertEquals(summarizeDashboardStatus(regressed).status, 'failing');

  const errored = emptyDashboardData();
  errored.current = { metadata: metadata('2026-05-24'), records: [record(0, 'error')] };
  assertEquals(summarizeDashboardStatus(errored).status, 'failing');
  assertIncludes(renderDashboardStatusSvg(summarizeDashboardStatus(errored)), '#d73a49');
});
