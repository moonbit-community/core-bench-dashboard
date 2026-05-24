import { restorePublishedHistory } from '../lib/history.ts';

export async function main(args = Deno.args): Promise<void> {
  const baseUrl = args[0] ?? '';
  const restored = await restorePublishedHistory(baseUrl);
  console.log(
    restored === 0
      ? 'No published core benchmark history restored.'
      : `Restored ${restored} published core benchmark history days.`,
  );
}

if (import.meta.main) {
  await main();
}
