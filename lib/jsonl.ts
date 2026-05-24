import { JsonStringifyStream } from '@std/json';
import { dirname } from '@std/path/dirname';
import type { CoreBenchJsonl, CoreBenchMetadata, CoreBenchRecord } from './types.ts';

export async function writeCoreBenchJsonl(
  path: string,
  metadata: CoreBenchMetadata,
  records: CoreBenchRecord[],
): Promise<void> {
  await Deno.mkdir(dirname(path), { recursive: true });
  using file = await Deno.open(path, { create: true, write: true, truncate: true });
  await ReadableStream.from([metadata, ...records])
    .pipeThrough(new JsonStringifyStream())
    .pipeThrough(new TextEncoderStream())
    .pipeTo(file.writable);
}

export function parseJsonlText(text: string): unknown[] {
  return text
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line));
}

export async function readCoreBenchJsonl(path: string): Promise<CoreBenchJsonl> {
  let text: string;
  try {
    text = await Deno.readTextFile(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return { metadata: null, records: [] };
    }
    throw error;
  }

  const values = parseJsonlText(text);
  return {
    metadata: (values[0] as CoreBenchMetadata | undefined) ?? null,
    records: values.slice(1) as CoreBenchRecord[],
  };
}

export function stringifyJsonl(metadata: CoreBenchMetadata, records: CoreBenchRecord[]): string {
  return `${[metadata, ...records].map((value) => JSON.stringify(value)).join('\n')}\n`;
}
