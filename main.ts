import { parseArgs } from '@std/cli/parse-args';
import { join } from '@std/path/join';
import { collectCoreBench } from './lib/collector.ts';
import { writeCoreBenchJsonl } from './lib/jsonl.ts';
import { CORE_BENCH_BACKENDS, CoreBenchBackend, CoreBenchOS, DASHBOARD_OS } from './lib/types.ts';

type Cli = {
  subcommand: 'collect';
  options: {
    coreDir: string;
    os: CoreBenchOS;
    backends: CoreBenchBackend[];
    outDir: string;
    benchTimeoutSeconds?: number;
  };
};

function showHelp() {
  console.log(`
Core Benchmark Dashboard

USAGE:
    deno run -A main.ts <SUBCOMMAND> [OPTIONS]

SUBCOMMANDS:
    collect          Run moon bench against a checked-out moonbitlang/core tree

GLOBAL OPTIONS:
    -h, --help       Show this help message
`);
}

function showCollectHelp() {
  console.log(`
Run core benchmark collection

USAGE:
    deno run -A main.ts collect --core-dir <PATH> [OPTIONS]

OPTIONS:
    --core-dir <PATH>                 Path to a moonbitlang/core checkout
    --os <OS>                         linux-x64 [default: linux-x64]
    --backends <LIST>                 Comma-separated backends [default: wasm,wasm-gc,js,native]
    --out-dir <PATH>                  Output directory [default: data/core-bench/current/linux-x64]
    --bench-timeout-seconds <NUMBER>  Timeout per backend [default: 3600]
    -h, --help                        Show this help message
`);
}

function parseOs(value: unknown): CoreBenchOS {
  if (value === undefined || value === DASHBOARD_OS) return DASHBOARD_OS;
  throw new Error(`Invalid --os value: ${String(value)}. Expected ${DASHBOARD_OS}.`);
}

function parseBackends(value: unknown): CoreBenchBackend[] {
  const raw = value === undefined ? CORE_BENCH_BACKENDS.join(',') : String(value);
  const backends = raw.split(',').map((item) => item.trim()).filter(Boolean);
  const invalid = backends.find((backend) => !CORE_BENCH_BACKENDS.includes(backend as CoreBenchBackend));
  if (invalid) {
    throw new Error(`Invalid backend: ${invalid}. Expected one of ${CORE_BENCH_BACKENDS.join(', ')}.`);
  }
  return backends as CoreBenchBackend[];
}

function parseCollectArgs(args: string[]): Cli {
  const parsed = parseArgs(args, {
    string: ['core-dir', 'os', 'backends', 'out-dir', 'bench-timeout-seconds'],
    boolean: ['help'],
    alias: { h: 'help' },
  });

  if (parsed.help) {
    showCollectHelp();
    Deno.exit(0);
  }

  if (!parsed['core-dir']) {
    throw new Error('--core-dir is required.');
  }

  const os = parseOs(parsed.os);
  return {
    subcommand: 'collect',
    options: {
      coreDir: parsed['core-dir'],
      os,
      backends: parseBackends(parsed.backends),
      outDir: parsed['out-dir'] ?? join('data/core-bench/current', os),
      benchTimeoutSeconds: parsed['bench-timeout-seconds'] ? Number(parsed['bench-timeout-seconds']) : undefined,
    },
  };
}

function parseCli(args: string[]): Cli {
  const parsed = parseArgs(args, {
    boolean: ['help'],
    alias: { h: 'help' },
    stopEarly: true,
  });

  if (parsed.help) {
    showHelp();
    Deno.exit(0);
  }

  const subcommand = parsed._[0]?.toString();
  const rest = parsed._.slice(1).map(String);
  switch (subcommand) {
    case 'collect':
      return parseCollectArgs(rest);
    default:
      throw new Error(subcommand ? `Unknown subcommand: ${subcommand}` : 'No subcommand specified.');
  }
}

try {
  const cli = parseCli(Deno.args);
  const result = await collectCoreBench(cli.options);
  const path = join(result.outDir, 'data.jsonl');
  await writeCoreBenchJsonl(path, result.metadata, result.records);
  console.log(`Wrote ${result.records.length} core benchmark records to ${path}`);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  Deno.exit(1);
}
