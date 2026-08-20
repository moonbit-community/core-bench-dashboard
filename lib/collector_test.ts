import { join } from '@std/path/join';
import { assertEquals, assertIncludes } from './assert.ts';
import { collectCoreBench } from './collector.ts';
import { DASHBOARD_OS } from './types.ts';

async function run(command: string, args: string[], cwd: string): Promise<void> {
  const process = new Deno.Command(command, { args, cwd, stdout: 'piped', stderr: 'piped' });
  const output = await process.output();
  if (!output.success) {
    throw new Error(`${command} ${args.join(' ')} failed: ${new TextDecoder().decode(output.stderr)}`);
  }
}

async function initGitRepo(path: string): Promise<void> {
  await Deno.mkdir(path, { recursive: true });
  await run('git', ['init'], path);
  await run('git', ['config', 'user.email', 'test@example.com'], path);
  await run('git', ['config', 'user.name', 'Test User'], path);
  await Deno.writeTextFile(join(path, 'README.md'), '# test\n');
  await run('git', ['add', 'README.md'], path);
  await run('git', ['commit', '-m', 'initial'], path);
}

Deno.test('collectCoreBench runs moon bench, captures logs, and parses records', async () => {
  const root = await Deno.makeTempDir();
  const oldPath = Deno.env.get('PATH') ?? '';

  try {
    const coreDir = join(root, 'core');
    const binDir = join(root, 'bin');
    const outDir = join(root, 'out');
    await initGitRepo(coreDir);
    await Deno.mkdir(binDir, { recursive: true });

    const fakeMoon = join(binDir, 'moon');
    await Deno.writeTextFile(
      fakeMoon,
      `#!/usr/bin/env sh
if [ "$1" = "version" ]; then
  echo "moon test"
  exit 0
fi
echo "stderr line" >&2
cat <<'EOF'
[moonbitlang/core] bench random/random_test.mbt:108 ("bench random") ok
time (mean ± σ)         range (min … max)
   1.25 µs ±   0.25 µs     1.00 µs …   1.50 µs  in 10 ×    800 runs
Total tests: 1, passed: 1, failed: 0.
EOF
`,
    );
    await Deno.chmod(fakeMoon, 0o755);
    Deno.env.set('PATH', `${binDir}:${oldPath}`);

    const result = await collectCoreBench({
      coreDir,
      os: DASHBOARD_OS,
      backends: ['wasm'],
      outDir,
      benchTimeoutSeconds: 10,
    });

    assertEquals(result.metadata.toolchainVersion, ['moon test']);
    assertEquals(result.metadata.coreCommitSha.length, 40);
    assertEquals(result.records.length, 1);
    assertEquals(result.records[0].mean_us, 1.25);
    assertIncludes(result.records[0].expanded_command?.join(' '), 'moon bench --target wasm');
    assertIncludes(await Deno.readTextFile(result.records[0].stderr_path!), 'stderr line');
  } finally {
    Deno.env.set('PATH', oldPath);
    await Deno.remove(root, { recursive: true });
  }
});
