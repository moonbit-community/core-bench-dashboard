import { basename } from '@std/path/basename';
import { dirname } from '@std/path/dirname';
import { join } from '@std/path/join';
import { parseJsonlText, readCoreBenchJsonl, stringifyJsonl } from './jsonl.ts';
import { DASHBOARD_OS, HistoryIndex } from './types.ts';

export const DEFAULT_HISTORY_RETENTION_DAYS = 14;

function normalizeBaseUrl(value: string): string {
  return value.trim().replace(/\/+$/, '');
}

async function fetchText(url: string): Promise<string | undefined> {
  const response = await fetch(url, { cache: 'no-store' }).catch(() => undefined);
  if (!response?.ok) return undefined;
  return await response.text();
}

function isDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

async function copyLogFromPublished(baseUrl: string, localDataDir: string, path: string): Promise<void> {
  const text = await fetchText(`${baseUrl}/${path}`);
  if (text === undefined) return;
  const relative = path.replace(/^data\/core-bench\//, '');
  const localPath = join(localDataDir, relative);
  await Deno.mkdir(dirname(localPath), { recursive: true });
  await Deno.writeTextFile(localPath, text);
}

export async function restorePublishedHistory(baseUrlValue: string, dataDir = 'data/core-bench'): Promise<number> {
  const baseUrl = normalizeBaseUrl(baseUrlValue);
  if (!baseUrl) return 0;

  const indexText = await fetchText(`${baseUrl}/data/core-bench/history/index.json`);
  if (indexText === undefined) return 0;

  const index = JSON.parse(indexText) as HistoryIndex;
  await Deno.mkdir(join(dataDir, 'history'), { recursive: true });
  await Deno.writeTextFile(join(dataDir, 'history', 'index.json'), `${JSON.stringify(index, null, 2)}\n`);

  let restored = 0;
  for (const day of index.days) {
    const jsonlText = await fetchText(`${baseUrl}/${day.path}`);
    if (jsonlText === undefined) continue;
    const localJsonlPath = join(dataDir, day.path.replace(/^data\/core-bench\//, ''));
    await Deno.mkdir(dirname(localJsonlPath), { recursive: true });
    await Deno.writeTextFile(localJsonlPath, jsonlText);
    restored += 1;

    const values = parseJsonlText(jsonlText);
    for (const value of values.slice(1)) {
      const record = value as { stdout_path?: string; stderr_path?: string };
      if (record.stdout_path) await copyLogFromPublished(baseUrl, dataDir, record.stdout_path);
      if (record.stderr_path) await copyLogFromPublished(baseUrl, dataDir, record.stderr_path);
    }
  }

  return restored;
}

function rewritePathToHistory(path: string | undefined, date: string, dataDir: string): string | undefined {
  if (!path) return undefined;
  return join(dataDir, 'history', date, DASHBOARD_OS, 'logs', basename(path));
}

async function copyCurrentLogsToHistory(date: string, dataDir: string): Promise<void> {
  const currentLogDir = join(dataDir, 'current', DASHBOARD_OS, 'logs');
  const historyLogDir = join(dataDir, 'history', date, DASHBOARD_OS, 'logs');
  const stat = await Deno.stat(currentLogDir).catch(() => undefined);
  if (!stat?.isDirectory) return;
  await Deno.mkdir(historyLogDir, { recursive: true });
  for await (const entry of Deno.readDir(currentLogDir)) {
    if (!entry.isFile) continue;
    await Deno.copyFile(join(currentLogDir, entry.name), join(historyLogDir, entry.name));
  }
}

async function listHistoryDates(dataDir: string): Promise<string[]> {
  const historyDir = join(dataDir, 'history');
  const stat = await Deno.stat(historyDir).catch(() => undefined);
  if (!stat?.isDirectory) return [];

  const dates: string[] = [];
  for await (const entry of Deno.readDir(historyDir)) {
    if (entry.isDirectory && isDate(entry.name)) dates.push(entry.name);
  }
  return dates.sort();
}

async function removePrunedDates(dataDir: string, keepDates: Set<string>): Promise<void> {
  for (const date of await listHistoryDates(dataDir)) {
    if (keepDates.has(date)) continue;
    await Deno.remove(join(dataDir, 'history', date), { recursive: true }).catch(() => {});
  }
}

export async function updateHistory(
  dataDir = 'data/core-bench',
  date = new Date().toISOString().slice(0, 10),
  retentionDays = DEFAULT_HISTORY_RETENTION_DAYS,
): Promise<HistoryIndex> {
  if (!isDate(date)) throw new Error(`Invalid history date: ${date}`);

  const currentPath = join(dataDir, 'current', DASHBOARD_OS, 'data.jsonl');
  const current = await readCoreBenchJsonl(currentPath);
  if (!current.metadata) throw new Error(`Current data is missing metadata: ${currentPath}`);

  await copyCurrentLogsToHistory(date, dataDir);
  const historyRecords = current.records.map((record) => ({
    ...record,
    stdout_path: rewritePathToHistory(record.stdout_path, date, dataDir),
    stderr_path: rewritePathToHistory(record.stderr_path, date, dataDir),
  }));

  const historyDataPath = join(dataDir, 'history', date, DASHBOARD_OS, 'data.jsonl');
  await Deno.mkdir(dirname(historyDataPath), { recursive: true });
  await Deno.writeTextFile(historyDataPath, stringifyJsonl(current.metadata, historyRecords));

  const keepDates = (await listHistoryDates(dataDir)).toSorted().slice(-retentionDays);
  await removePrunedDates(dataDir, new Set(keepDates));

  const index: HistoryIndex = {
    generated_at: new Date().toISOString(),
    retention_days: retentionDays,
    days: keepDates.map((historyDate) => ({
      date: historyDate,
      os: DASHBOARD_OS,
      path: join(dataDir, 'history', historyDate, DASHBOARD_OS, 'data.jsonl'),
    })),
  };

  await Deno.mkdir(join(dataDir, 'history'), { recursive: true });
  await Deno.writeTextFile(join(dataDir, 'history', 'index.json'), `${JSON.stringify(index, null, 2)}\n`);
  return index;
}
