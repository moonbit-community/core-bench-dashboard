import { join } from '@std/path/join';
import { assertEquals } from './assert.ts';
import { readCoreBenchJsonl, writeCoreBenchJsonl } from './jsonl.ts';
import { updateHistory } from './history.ts';
import { type CoreBenchMetadata, type CoreBenchRecord, DASHBOARD_OS } from './types.ts';

function metadata(date: string): CoreBenchMetadata {
  return {
    generated_at: `${date}T00:00:00.000Z`,
    runId: '1',
    runNumber: '1',
    os: DASHBOARD_OS,
    backends: ['wasm'],
    toolchainVersion: ['moon test'],
    coreRepo: 'https://github.com/moonbitlang/core',
    coreCommitSha: 'a'.repeat(40),
  };
}

function record(mean: number, stdoutPath: string, stderrPath: string): CoreBenchRecord {
  return {
    benchmark_id: 'wasm|pkg|file.mbt|1|bench|',
    backend: 'wasm',
    package: 'moonbitlang/core/pkg',
    file: 'pkg/file.mbt',
    line: 1,
    block_label: 'bench',
    case_name: '',
    status: 'ok',
    mean_us: mean,
    stdout_path: stdoutPath,
    stderr_path: stderrPath,
  };
}

async function writeCurrent(root: string, date: string, mean: number): Promise<void> {
  const dataDir = join(root, 'data/core-bench');
  const outDir = join(dataDir, `current/${DASHBOARD_OS}`);
  const stdout = join(outDir, 'logs/stdout.log');
  const stderr = join(outDir, 'logs/stderr.log');
  await Deno.mkdir(join(outDir, 'logs'), { recursive: true });
  await Deno.writeTextFile(stdout, `stdout ${mean}\n`);
  await Deno.writeTextFile(stderr, `stderr ${mean}\n`);
  await writeCoreBenchJsonl(join(outDir, 'data.jsonl'), metadata(date), [record(mean, stdout, stderr)]);
}

Deno.test('updateHistory replaces same-day entries, rewrites log paths, and prunes to retention', async () => {
  const root = await Deno.makeTempDir();
  const dataDir = join(root, 'data/core-bench');
  try {
    for (let day = 1; day <= 15; day += 1) {
      await Deno.mkdir(join(dataDir, 'history', `2026-05-${String(day).padStart(2, '0')}`), { recursive: true });
    }

    await writeCurrent(root, '2026-05-24', 10);
    let index = await updateHistory(dataDir, '2026-05-24', 14);
    assertEquals(index.days.length, 14);
    assertEquals(index.days[0].date, '2026-05-03');
    assertEquals(index.days.at(-1)?.date, '2026-05-24');

    let history = await readCoreBenchJsonl(join(dataDir, `history/2026-05-24/${DASHBOARD_OS}/data.jsonl`));
    assertEquals(history.records[0].mean_us, 10);
    assertEquals(history.records[0].stdout_path, join(dataDir, `history/2026-05-24/${DASHBOARD_OS}/logs/stdout.log`));
    assertEquals(await Deno.readTextFile(history.records[0].stdout_path!), 'stdout 10\n');

    await writeCurrent(root, '2026-05-24', 20);
    index = await updateHistory(dataDir, '2026-05-24', 14);
    history = await readCoreBenchJsonl(join(dataDir, `history/2026-05-24/${DASHBOARD_OS}/data.jsonl`));
    assertEquals(index.days.filter((day) => day.date === '2026-05-24').length, 1);
    assertEquals(history.records[0].mean_us, 20);
    assertEquals(await Deno.readTextFile(history.records[0].stdout_path!), 'stdout 20\n');
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
