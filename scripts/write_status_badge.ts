import { parseArgs } from '@std/cli/parse-args';
import { dirname } from '@std/path/dirname';
import { join } from '@std/path/join';
import { emptyDashboardData } from '../lib/dashboard_data.ts';
import { renderDashboardStatusSvg, summarizeDashboardStatus } from '../lib/dashboard_status.ts';
import { readCoreBenchJsonl } from '../lib/jsonl.ts';
import type { HistoryIndex } from '../lib/types.ts';

function showHelp() {
  console.log(`
Write core benchmark dashboard status badge

USAGE:
    deno run -A scripts/write_status_badge.ts [OPTIONS]

OPTIONS:
    --data-dir <PATH>    Core benchmark data directory [default: data/core-bench]
    --out <PATH>         Badge SVG output path [default: <data-dir>/status.svg]
    -h, --help           Show this help message
`);
}

async function readHistory(dataDir: string): Promise<ReturnType<typeof emptyDashboardData>['history']> {
  const indexPath = join(dataDir, 'history', 'index.json');
  let index: HistoryIndex;
  try {
    index = JSON.parse(await Deno.readTextFile(indexPath)) as HistoryIndex;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }

  const history = [];
  for (const day of index.days) {
    history.push({ date: day.date, data: await readCoreBenchJsonl(day.path) });
  }
  return history;
}

export async function main(args = Deno.args): Promise<void> {
  const parsed = parseArgs(args, {
    string: ['data-dir', 'out'],
    boolean: ['help'],
    alias: { h: 'help' },
  });

  if (parsed.help) {
    showHelp();
    return;
  }

  const dataDir = parsed['data-dir'] ?? 'data/core-bench';
  const outPath = parsed.out ?? join(dataDir, 'status.svg');
  const data = emptyDashboardData();
  data.current = await readCoreBenchJsonl(join(dataDir, 'current', 'linux-x64', 'data.jsonl'));
  data.history = await readHistory(dataDir);

  const summary = summarizeDashboardStatus(data);
  await Deno.mkdir(dirname(outPath), { recursive: true });
  await Deno.writeTextFile(outPath, renderDashboardStatusSvg(summary));
  console.log(
    `Wrote ${summary.status} dashboard badge to ${outPath} ` +
      `(${summary.regressionCount} regressions, ${summary.errorCount} errors).`,
  );
}

if (import.meta.main) {
  await main();
}
