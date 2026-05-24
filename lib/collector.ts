import { join } from '@std/path/join';
import { CORE_REPO, CoreBenchBackend, CoreBenchMetadata, CoreBenchOS, CoreBenchRecord } from './types.ts';
import { parseMoonBenchOutput } from './bench_parser.ts';
import { sha256Hex } from './log.ts';
import { getMoonVersion } from './moon.ts';

const DEFAULT_BENCH_TIMEOUT_SECONDS = 3600;

export interface CollectOptions {
  coreDir: string;
  os: CoreBenchOS;
  backends: CoreBenchBackend[];
  outDir: string;
  benchTimeoutSeconds?: number;
}

interface ProcessResult {
  success: boolean;
  code: number;
  elapsed: number;
  reason?: string;
}

async function runGit(args: string[], cwd: string): Promise<string> {
  const process = new Deno.Command('git', { args, cwd, stdout: 'piped', stderr: 'piped' });
  const { code, stdout, stderr } = await process.output();
  const stdoutText = new TextDecoder().decode(stdout).trim();
  if (code !== 0) {
    const stderrText = new TextDecoder().decode(stderr).trim();
    throw new Error(`git ${args.join(' ')} failed with exit code ${code}${stderrText ? `: ${stderrText}` : ''}`);
  }
  return stdoutText;
}

async function readCoreCommit(coreDir: string): Promise<string> {
  const stat = await Deno.stat(coreDir).catch(() => undefined);
  if (!stat?.isDirectory) {
    throw new Error(`--core-dir does not exist or is not a directory: ${coreDir}`);
  }
  return await runGit(['rev-parse', 'HEAD'], coreDir);
}

async function readToolchainVersion(): Promise<string[]> {
  try {
    return await getMoonVersion();
  } catch (error) {
    return [`unavailable: ${error instanceof Error ? error.message : String(error)}`];
  }
}

async function logPaths(outDir: string, backend: CoreBenchBackend): Promise<{ stdout: string; stderr: string }> {
  await Deno.mkdir(join(outDir, 'logs'), { recursive: true });
  const prefix = (await sha256Hex(`core|linux-x64|${backend}`)).slice(0, 16);
  return {
    stdout: join(outDir, 'logs', `${prefix}.${backend}.stdout.log`),
    stderr: join(outDir, 'logs', `${prefix}.${backend}.stderr.log`),
  };
}

function commandForBackend(backend: CoreBenchBackend, targetDir: string): string[] {
  return [
    'moon',
    'bench',
    '--target',
    backend,
    '--target-dir',
    targetDir,
    '--frozen',
    '--no-parallelize',
  ];
}

async function runBenchCommand(
  args: string[],
  cwd: string,
  timeoutSeconds: number,
  stdoutPath: string,
  stderrPath: string,
): Promise<ProcessResult> {
  const started = performance.now();
  const signal = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    signal.abort();
  }, timeoutSeconds * 1000);

  try {
    using stdoutFile = await Deno.open(stdoutPath, { create: true, write: true, truncate: true });
    using stderrFile = await Deno.open(stderrPath, { create: true, write: true, truncate: true });
    const process = new Deno.Command(args[0], {
      args: args.slice(1),
      cwd,
      signal: signal.signal,
      stdout: 'piped',
      stderr: 'piped',
    });
    const child = process.spawn();
    const stdoutTask = child.stdout.pipeTo(stdoutFile.writable);
    const stderrTask = child.stderr.pipeTo(stderrFile.writable);

    try {
      const status = await child.status;
      await Promise.all([stdoutTask, stderrTask]);
      return {
        success: status.success,
        code: status.code,
        elapsed: Math.round((performance.now() - started) / 10) / 100,
      };
    } catch (error) {
      await Promise.allSettled([stdoutTask, stderrTask]);
      return {
        success: false,
        code: timedOut ? 124 : 1,
        elapsed: Math.round((performance.now() - started) / 10) / 100,
        reason: timedOut ? `Command timed out after ${timeoutSeconds} seconds.` : String(error),
      };
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await Deno.writeTextFile(stderrPath, message).catch(() => {});
    return {
      success: false,
      code: timedOut ? 124 : 1,
      elapsed: Math.round((performance.now() - started) / 10) / 100,
      reason: timedOut ? `Command timed out after ${timeoutSeconds} seconds.` : message,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function commandErrorRecord(
  backend: CoreBenchBackend,
  stdoutPath: string,
  stderrPath: string,
  expandedCommand: string[],
  reason: string,
): CoreBenchRecord {
  return {
    benchmark_id: `${backend}|moon bench command`,
    backend,
    package: 'moonbitlang/core',
    file: '',
    line: 0,
    block_label: 'moon bench command',
    case_name: '',
    status: 'error',
    stdout_path: stdoutPath,
    stderr_path: stderrPath,
    reason,
    expanded_command: expandedCommand,
  };
}

async function collectBackend(
  options: CollectOptions,
  backend: CoreBenchBackend,
  tempRoot: string,
): Promise<CoreBenchRecord[]> {
  const paths = await logPaths(options.outDir, backend);
  const targetDir = join(tempRoot, backend, 'build');
  await Deno.mkdir(targetDir, { recursive: true });
  const command = commandForBackend(backend, targetDir);
  const result = await runBenchCommand(
    command,
    options.coreDir,
    options.benchTimeoutSeconds ?? DEFAULT_BENCH_TIMEOUT_SECONDS,
    paths.stdout,
    paths.stderr,
  );

  if (!result.success) {
    const stderr = await Deno.readTextFile(paths.stderr).catch(() => '');
    const reason = result.reason ??
      `moon bench failed with exit code ${result.code}${stderr.trim() ? `: ${stderr.trim().slice(0, 500)}` : ''}`;
    return [commandErrorRecord(backend, paths.stdout, paths.stderr, command, reason)];
  }

  const stdout = await Deno.readTextFile(paths.stdout);
  const records = parseMoonBenchOutput(stdout, backend).map((record) => ({
    ...record,
    stdout_path: paths.stdout,
    stderr_path: paths.stderr,
    expanded_command: command,
  }));

  if (records.length === 0) {
    return [commandErrorRecord(backend, paths.stdout, paths.stderr, command, 'moon bench produced no parsed records.')];
  }

  return records;
}

export async function collectCoreBench(
  options: CollectOptions,
): Promise<{ metadata: CoreBenchMetadata; records: CoreBenchRecord[]; outDir: string }> {
  const coreCommitSha = await readCoreCommit(options.coreDir);
  const tempRoot = await Deno.makeTempDir({ prefix: 'core-bench-' });
  const records: CoreBenchRecord[] = [];

  try {
    for (const backend of options.backends) {
      records.push(...await collectBackend(options, backend, tempRoot));
    }
  } finally {
    await Deno.remove(tempRoot, { recursive: true }).catch(() => {});
  }

  return {
    outDir: options.outDir,
    metadata: {
      generated_at: new Date().toISOString(),
      runId: Deno.env.get('GITHUB_ACTION_RUN_ID') || '0',
      runNumber: Deno.env.get('GITHUB_ACTION_RUN_NUMBER') || '0',
      os: options.os,
      backends: [...options.backends],
      toolchainVersion: await readToolchainVersion(),
      coreRepo: CORE_REPO,
      coreCommitSha,
    },
    records,
  };
}
