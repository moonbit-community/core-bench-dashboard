import { html, render } from 'npm:htm@3.1.1/preact';
import { useEffect, useMemo, useState } from 'npm:preact@10.27.2/hooks';
import {
  buildRows,
  countRows,
  DashboardData,
  DashboardRow,
  emptyDashboardData,
  Filter,
  filterRows,
} from './lib/dashboard_data.ts';
import {
  CORE_BENCH_BACKENDS,
  CoreBenchCellState,
  CoreBenchJsonl,
  CoreBenchRecord,
  DASHBOARD_OS,
  HistoryIndex,
} from './lib/types.ts';

const STATE_COLORS: Record<CoreBenchCellState, { bg: string; fg: string; border: string }> = {
  regression: { bg: '#fee2e2', fg: '#991b1b', border: '#ef4444' },
  improvement: { bg: '#dcfce7', fg: '#166534', border: '#22c55e' },
  stable: { bg: '#eef2ff', fg: '#3730a3', border: '#a5b4fc' },
  new: { bg: '#fef3c7', fg: '#92400e', border: '#f59e0b' },
  missing: { bg: '#e5e7eb', fg: '#374151', border: '#9ca3af' },
  error: { bg: '#7f1d1d', fg: '#ffffff', border: '#7f1d1d' },
};

const STATE_LABELS: Record<CoreBenchCellState, string> = {
  regression: 'REG',
  improvement: 'IMP',
  stable: 'OK',
  new: 'NEW',
  missing: 'MISS',
  error: 'ERR',
};

async function readJsonl(url: string): Promise<CoreBenchJsonl> {
  const response = await fetch(url, { cache: 'no-store' }).catch(() => undefined);
  if (!response?.ok) return { metadata: null, records: [] };
  const values = (await response.text())
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line));
  return {
    metadata: (values[0] as CoreBenchJsonl['metadata'] | undefined) ?? null,
    records: values.slice(1) as CoreBenchRecord[],
  };
}

async function readHistoryIndex(): Promise<HistoryIndex | null> {
  const response = await fetch('data/core-bench/history/index.json', { cache: 'no-store' }).catch(() => undefined);
  if (!response?.ok) return null;
  return await response.json() as HistoryIndex;
}

function pad2(value: number): string {
  return value.toString().padStart(2, '0');
}

function formatGeneratedAt(value: string | undefined): string {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${
    pad2(date.getMinutes())
  }`;
}

function formatTime(us: number | undefined): string {
  if (us === undefined) return '-';
  if (us < 1) return `${(us * 1000).toFixed(2)} ns`;
  if (us < 1000) return `${us.toFixed(2)} us`;
  if (us < 1_000_000) return `${(us / 1000).toFixed(2)} ms`;
  return `${(us / 1_000_000).toFixed(2)} s`;
}

function formatDelta(delta: number | undefined): string {
  if (delta === undefined) return '';
  const sign = delta > 0 ? '+' : '';
  return `${sign}${delta.toFixed(1)}%`;
}

function shortCommit(commit: string | undefined): string {
  return commit ? commit.slice(0, 12) : '-';
}

async function openLogs(record: CoreBenchRecord | undefined, label: string) {
  let content = '';
  if (!record) {
    content = `No ${label} result record.`;
  } else {
    content += `${label}\n`;
    content += `benchmark_id: ${record.benchmark_id}\n`;
    content += `backend: ${record.backend}\n`;
    content += `package: ${record.package}\n`;
    content += `file: ${record.file}:${record.line}\n`;
    content += `label: ${record.block_label}${record.case_name ? ` / ${record.case_name}` : ''}\n`;
    content += `status: ${record.status}\n`;
    if (record.expanded_command) content += `command: ${record.expanded_command.join(' ')}\n`;
    if (record.reason) content += `reason: ${record.reason}\n`;
    content += '\n';

    try {
      if (record.stderr_path) {
        const stderr = await fetch(record.stderr_path);
        content += `STDERR:\n${stderr.ok ? await stderr.text() : `Failed to fetch ${record.stderr_path}`}\n\n`;
      }
      if (record.stdout_path) {
        const stdout = await fetch(record.stdout_path);
        content += `STDOUT:\n${stdout.ok ? await stdout.text() : `Failed to fetch ${record.stdout_path}`}\n`;
      }
    } catch (error) {
      content += `Failed to fetch logs: ${error instanceof Error ? error.message : String(error)}\n`;
    }
  }

  const blob = new Blob([content], { type: 'text/plain;charset=utf8' });
  const url = URL.createObjectURL(blob);
  const tab = globalThis.open(url, '_blank');
  if (tab) setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function StateBadge({ state }: { state: CoreBenchCellState }) {
  const color = STATE_COLORS[state];
  return html`
    <span
      style="display: inline-flex; min-width: 44px; justify-content: center; border: 1px solid ${color
        .border}; border-radius: 4px; background: ${color.bg}; color: ${color
        .fg}; padding: 2px 5px; font-size: 10px; font-weight: 800;"
    >
      ${STATE_LABELS[state]}
    </span>
  `;
}

function BackendCellView({ row, backend }: { row: DashboardRow; backend: (typeof CORE_BENCH_BACKENDS)[number] }) {
  const cell = row.cells.get(backend);
  const color = STATE_COLORS[cell?.state ?? 'missing'];
  const record = cell?.current;
  const title = `${backend} ${cell?.state ?? 'missing'} ${formatDelta(cell?.deltaPercent)}`;
  return html`
    <td
      title="${title}"
      onClick="${record ? () => openLogs(record, `${backend} current`) : undefined}"
      style="border: 1px solid ${color.border}; background: ${color.bg}; color: ${color
        .fg}; padding: 6px; text-align: right; cursor: ${record ? 'pointer' : 'default'};"
    >
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 6px;">
        <${StateBadge} state="${cell?.state ?? 'missing'}" />
        <div style="font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-weight: 800;">
          ${formatTime(record?.mean_us)}
        </div>
      </div>
      <div style="margin-top: 3px; font-size: 11px; font-weight: 700;">
        ${formatDelta(cell?.deltaPercent)}
      </div>
    </td>
  `;
}

function SeriesCell({ record, date }: { record?: CoreBenchRecord; date: string }) {
  const label = record?.status === 'error' ? 'ERR' : record ? formatTime(record.mean_us) : '-';
  return html`
    <button
      title="${date}"
      onClick="${record ? () => openLogs(record, `${date} ${record.backend}`) : undefined}"
      style="width: 100%; min-height: 26px; border: 1px solid #d1d5db; border-radius: 4px; background: ${record
          ?.status ===
          'error'
        ? '#fee2e2'
        : record
        ? '#ffffff'
        : '#f3f4f6'}; color: #111827; cursor: ${record
        ? 'pointer'
        : 'default'}; font-size: 11px; font-family: ui-monospace, SFMono-Regular, Consolas, monospace;"
    >
      ${label}
    </button>
  `;
}

function ExpandedRow({ row }: { row: DashboardRow }) {
  const dates = row.series.get(CORE_BENCH_BACKENDS[0])?.map((point) => point.date) ?? [];
  return html`
    <div style="padding: 10px 12px; background: #f9fafb; border-top: 1px solid #e5e7eb;">
      <div
        style="display: grid; grid-template-columns: 90px repeat(${Math.max(
          dates.length,
          1,
        )}, minmax(72px, 1fr)); gap: 5px; align-items: center;"
      >
        <div style="font-size: 11px; font-weight: 800; color: #374151;">Backend</div>
        ${dates.map((date) =>
          html`
            <div style="font-size: 11px; font-weight: 800; color: #374151; text-align: center;">${date.slice(5)}</div>
          `
        )} ${CORE_BENCH_BACKENDS.flatMap((backend) => {
          const points = row.series.get(backend) ?? [];
          return [
            html`
              <div style="font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-weight: 800;">${backend}</div>
            `,
            ...points.map((point) =>
              html`
                <${SeriesCell} date="${point.date}" record="${point.record}" />
              `
            ),
          ];
        })}
      </div>
    </div>
  `;
}

function App() {
  const [data, setData] = useState<DashboardData>(emptyDashboardData());
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});

  useEffect(() => {
    async function fetchAll() {
      const next = emptyDashboardData();
      next.current = await readJsonl(`data/core-bench/current/${DASHBOARD_OS}/data.jsonl`);
      next.historyIndex = await readHistoryIndex();
      if (next.historyIndex) {
        next.history = await Promise.all(
          next.historyIndex.days.map(async (day) => ({ date: day.date, data: await readJsonl(day.path) })),
        );
      }
      setData(next);
      setLoading(false);
    }
    fetchAll();
  }, []);

  const rows = useMemo(() => buildRows(data), [data]);
  const filteredRows = useMemo(() => filterRows(rows, filter, search), [rows, filter, search]);
  const counts = useMemo(() => countRows(rows), [rows]);
  const metadata = data.current.metadata;
  const generatedAt = formatGeneratedAt(metadata?.generated_at);
  const toolchain = metadata?.toolchainVersion.join('\n').trim() || '-';
  const commit = shortCommit(metadata?.coreCommitSha);

  if (loading) {
    return html`
      <div style="padding: 20px; font-family: ui-sans-serif, system-ui;">Loading...</div>
    `;
  }

  return html`
    <div
      style="min-width: 960px; padding: 18px 20px 26px; font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #111827;"
    >
      <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 14px;">
        <div>
          <h1 style="margin: 0; font-size: 24px; line-height: 1.15;">Core Benchmark Dashboard</h1>
          <div style="margin-top: 4px; color: #4b5563; font-size: 13px;">moonbitlang/core main, ${DASHBOARD_OS}</div>
        </div>
        <div
          style="border: 1px solid #d1d5db; border-radius: 6px; background: #ffffff; padding: 8px 10px; min-width: 360px; font-size: 12px;"
        >
          <div><strong>Generated</strong> <time title="${metadata?.generated_at ?? ''}">${generatedAt}</time></div>
          <div style="margin-top: 3px;"><strong>Core</strong> ${commit}</div>
          <pre
            style="margin: 5px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 11px; line-height: 1.35;"
          >${toolchain}</pre>
        </div>
      </div>

      <div style="display: flex; flex-wrap: wrap; gap: 8px; align-items: stretch; margin-bottom: 12px;">
        ${([
          ['regression', 'Regressions', counts.regression],
          ['error', 'Errors', counts.error],
          ['missing', 'Missing', counts.missing],
          ['new', 'New', counts.new],
          ['improvement', 'Improved', counts.improvement],
          ['stable', 'Stable', counts.stable],
          ['all', 'Total', counts.all],
        ] as const).map(([key, label, value]) =>
          html`
            <button
              onClick="${() => setFilter(key)}"
              style="min-width: 104px; border: 1px solid ${filter === key
                ? '#111827'
                : '#d1d5db'}; border-radius: 6px; background: ${filter === key
                ? '#111827'
                : '#ffffff'}; color: ${filter === key
                ? '#ffffff'
                : '#111827'}; padding: 7px 9px; cursor: pointer; text-align: left;"
            >
              <div style="font-size: 11px; font-weight: 800;">${label}</div>
              <div style="font-size: 19px; font-weight: 900; line-height: 1.1;">${value}</div>
            </button>
          `
        )}
        <input
          type="text"
          placeholder="Search package, file, label"
          value="${search}"
          onInput="${(event: Event) => setSearch((event.target as HTMLInputElement).value)}"
          style="margin-left: auto; min-width: 280px; border: 1px solid #d1d5db; border-radius: 6px; padding: 7px 9px; align-self: center;"
        />
      </div>

      <div style="margin-bottom: 8px; font-size: 12px; color: #4b5563;">
        Showing ${filteredRows.length} of ${rows.length} benchmarks
      </div>

      <table style="width: 100%; border-collapse: collapse; font-size: 12px; table-layout: fixed; background: white;">
        <thead>
          <tr style="background: #263241; color: white;">
            <th style="padding: 8px; border: 1px solid #d1d5db; text-align: left; width: 260px;">Benchmark</th>
            <th style="padding: 8px; border: 1px solid #d1d5db; text-align: left; width: 230px;">Location</th>
            ${CORE_BENCH_BACKENDS.map((backend) =>
              html`
                <th style="padding: 8px; border: 1px solid #d1d5db;">${backend}</th>
              `
            )}
            <th style="padding: 8px; border: 1px solid #d1d5db; width: 76px;">Overall</th>
            <th style="padding: 8px; border: 1px solid #d1d5db; width: 78px;">Details</th>
          </tr>
        </thead>
        <tbody>
          ${filteredRows.map((row, index) => {
            const isExpanded = !!expanded[row.key];
            const label = row.case_name ? `${row.block_label} / ${row.case_name}` : row.block_label;
            return html`
              <tr style="background: ${index % 2 === 0 ? '#ffffff' : '#f9fafb'};">
                <td style="padding: 7px; border: 1px solid #d1d5db; overflow: hidden; text-overflow: ellipsis;" title="${label}">
                  <div style="font-weight: 800; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${label}</div>
                  <div
                    style="margin-top: 2px; color: #4b5563; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;"
                  >
                    ${row.package}
                  </div>
                </td>
                <td
                  style="padding: 7px; border: 1px solid #d1d5db; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; overflow: hidden; text-overflow: ellipsis;"
                  title="${row.file}:${row.line}"
                >
                  ${row.file}:${row.line}
                </td>
                ${CORE_BENCH_BACKENDS.map((backend) =>
                  html`
                    <${BackendCellView} row="${row}" backend="${backend}" />
                  `
                )}
                <td style="padding: 7px; border: 1px solid #d1d5db; text-align: center;">
                  <${StateBadge} state="${row.state}" />
                </td>
                <td style="padding: 7px; border: 1px solid #d1d5db; text-align: center;">
                  <button
                    onClick="${() => setExpanded((prev) => ({ ...prev, [row.key]: !prev[row.key] }))}"
                    style="border: 1px solid #d1d5db; border-radius: 5px; background: #ffffff; cursor: pointer; font-size: 11px; padding: 4px 8px;"
                  >
                    ${isExpanded ? 'Hide' : 'Show'}
                  </button>
                </td>
              </tr>
              ${isExpanded
                ? html`
                  <tr>
                    <td colspan="8" style="padding: 0; border: 1px solid #d1d5db; border-top: 0;">
                      <${ExpandedRow} row="${row}" />
                    </td>
                  </tr>
                `
                : ''}
            `;
          })}
        </tbody>
      </table>
    </div>
  `;
}

render(
  html`
    <${App} />
  `,
  document.body,
);
