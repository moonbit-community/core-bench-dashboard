import { parseArgs } from '@std/cli/parse-args';
import { DEFAULT_HISTORY_RETENTION_DAYS, updateHistory } from '../lib/history.ts';

function showHelp() {
  console.log(`
Update core benchmark history

USAGE:
    deno run -A scripts/update_history.ts [OPTIONS]

OPTIONS:
    --data-dir <PATH>       Core benchmark data directory [default: data/core-bench]
    --date <YYYY-MM-DD>     History date [default: today UTC]
    --retention-days <N>    Retained calendar days [default: 14]
    -h, --help              Show this help message
`);
}

export async function main(args = Deno.args): Promise<void> {
  const parsed = parseArgs(args, {
    string: ['data-dir', 'date', 'retention-days'],
    boolean: ['help'],
    alias: { h: 'help' },
  });

  if (parsed.help) {
    showHelp();
    return;
  }

  const index = await updateHistory(
    parsed['data-dir'] ?? 'data/core-bench',
    parsed.date ?? new Date().toISOString().slice(0, 10),
    parsed['retention-days'] ? Number(parsed['retention-days']) : DEFAULT_HISTORY_RETENTION_DAYS,
  );
  console.log(`Updated core benchmark history with ${index.days.length} retained days.`);
}

if (import.meta.main) {
  await main();
}
