import { dirname } from '@std/path/posix/dirname';
import type { BenchmarkIdentity, CoreBenchBackend, CoreBenchRecord } from './types.ts';

const ANSI_PATTERN = new RegExp(String.raw`\x1b\[[0-?]*[ -/]*[@-~]`, 'g');
const NUMBER = String.raw`[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?`;
const UNIT = String.raw`(?:ns|µs|μs|us|ms|s|min)`;
const TIME_PATTERN = new RegExp(
  String.raw`(?<mean>${NUMBER})\s*(?<meanUnit>${UNIT})\s*±\s*` +
    String.raw`(?<stddev>${NUMBER})\s*(?<stddevUnit>${UNIT})\s+` +
    String.raw`(?<min>${NUMBER})\s*(?<minUnit>${UNIT})\s*(?:…|\.\.\.)\s*` +
    String.raw`(?<max>${NUMBER})\s*(?<maxUnit>${UNIT})\s+in\s+` +
    String.raw`(?<runs>\d+)\s*×\s*(?<batchSize>\d+)\s+runs`,
);
const HEADER_PATTERN =
  /^\[(?<module>[^\]]+)\]\s+bench\s+(?<file>.*?):(?<line>\d+)\s+\("(?<label>(?:\\.|[^"])*)"\)\s+(?<result>\S+)/;

interface BenchContext {
  module: string;
  file: string;
  line: number;
  label: string;
}

interface TimingMatch {
  index: number;
  mean_us: number;
  stddev_us: number;
  min_us: number;
  max_us: number;
  runs: number;
  batch_size: number;
}

export function stripAnsi(value: string): string {
  return value.replace(ANSI_PATTERN, '');
}

export function normalizeTimeToMicroseconds(value: number, unit: string): number {
  switch (unit) {
    case 'ns':
      return value / 1000;
    case 'µs':
    case 'μs':
    case 'us':
      return value;
    case 'ms':
      return value * 1000;
    case 's':
      return value * 1_000_000;
    case 'min':
      return value * 60_000_000;
    default:
      throw new Error(`Unsupported benchmark time unit: ${unit}`);
  }
}

function unescapeLabel(value: string): string {
  return value.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
}

function packageFromFile(moduleName: string, file: string): string {
  const dir = dirname(file.replaceAll('\\', '/'));
  return dir === '.' ? moduleName : `${moduleName}/${dir}`;
}

function benchmarkId(backend: CoreBenchBackend, identity: BenchmarkIdentity): string {
  return [
    backend,
    identity.package,
    identity.file,
    String(identity.line),
    identity.block_label,
    identity.case_name,
  ].join('|');
}

function parseHeader(line: string): BenchContext | undefined {
  const match = HEADER_PATTERN.exec(line);
  const groups = match?.groups;
  if (!groups) return undefined;
  return {
    module: groups.module,
    file: groups.file,
    line: Number(groups.line),
    label: unescapeLabel(groups.label),
  };
}

function parseTimingLine(line: string): TimingMatch | undefined {
  const match = TIME_PATTERN.exec(line);
  const groups = match?.groups;
  if (!groups) return undefined;

  return {
    index: match.index,
    mean_us: normalizeTimeToMicroseconds(Number(groups.mean), groups.meanUnit),
    stddev_us: normalizeTimeToMicroseconds(Number(groups.stddev), groups.stddevUnit),
    min_us: normalizeTimeToMicroseconds(Number(groups.min), groups.minUnit),
    max_us: normalizeTimeToMicroseconds(Number(groups.max), groups.maxUnit),
    runs: Number(groups.runs),
    batch_size: Number(groups.batchSize),
  };
}

function recordFromTiming(
  backend: CoreBenchBackend,
  context: BenchContext,
  caseName: string,
  timing: TimingMatch,
): CoreBenchRecord {
  const identity: BenchmarkIdentity = {
    package: packageFromFile(context.module, context.file),
    file: context.file,
    line: context.line,
    block_label: context.label,
    case_name: caseName,
  };
  return {
    benchmark_id: benchmarkId(backend, identity),
    backend,
    ...identity,
    status: 'ok',
    mean_us: timing.mean_us,
    stddev_us: timing.stddev_us,
    min_us: timing.min_us,
    max_us: timing.max_us,
    runs: timing.runs,
    batch_size: timing.batch_size,
  };
}

export function parseMoonBenchOutput(stdout: string, backend: CoreBenchBackend): CoreBenchRecord[] {
  const lines = stripAnsi(stdout).split(/\r?\n/);
  const records: CoreBenchRecord[] = [];
  let context: BenchContext | undefined;
  let inTimeTable = false;
  let batchTable = false;

  for (const line of lines) {
    const header = parseHeader(line);
    if (header) {
      context = header;
      inTimeTable = false;
      batchTable = false;
      continue;
    }

    if (!context) continue;

    if (line.includes('time (mean') && line.includes('range')) {
      inTimeTable = true;
      batchTable = line.trimStart().startsWith('name');
      continue;
    }

    if (!inTimeTable) continue;
    if (!line.trim() || line.startsWith('Total tests:')) {
      inTimeTable = false;
      continue;
    }

    const timing = parseTimingLine(line);
    if (!timing) continue;

    const caseName = batchTable ? line.slice(0, timing.index).trim() : '';
    records.push(recordFromTiming(backend, context, caseName, timing));
  }

  return records;
}
