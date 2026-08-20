# Operations

## Runners

`collect-data` runs on a self-hosted Apple Silicon macOS runner carrying the `self-hosted` and `bench-box` labels.
`publish-site` stays on `ubuntu-latest`, so a deploy never waits on the bench machine.

Because a self-hosted workspace persists between runs, `collect-data` starts by removing `core` and `data`. The runner
needs `git`, `curl`, and Xcode Command Line Tools; Deno and the MoonBit nightly toolchain are installed per run.

## Phases

CI performs four phases:

1. Install Deno and the nightly MoonBit toolchain.
2. Clone `https://github.com/moonbitlang/core` at `main`.
3. Run `moon bench --target <backend> --target-dir <tmp/build> --frozen --no-parallelize` for `wasm`, `wasm-gc`, `js`,
   and `native`.
4. Restore published history, add or replace the current day, prune to 14 days, generate `status.svg`, bundle `web.ts`,
   and deploy the static site to GitHub Pages.

The badge is red if any current cell is a 5% or larger regression versus the previous retained day, or if a backend
benchmark command failed. It is green otherwise.

## Changing the benchmark platform

`DASHBOARD_OS` in `lib/types.ts` names the single platform the dashboard publishes. Retained history is keyed by date
only, so history collected on a different platform must not be carried across a change of that constant: the regenerated
index would point at paths that do not exist for older days, and every benchmark would silently read as `new`.

To break the chain, point the restore at a URL that does not resolve for exactly one run. `restorePublishedHistory`
returns early when the history index cannot be fetched, so nothing is restored and no workflow edit is needed:

```sh
gh variable set PAGES_BASE_URL --body 'https://invalid.invalid'
gh workflow run core-bench.yml
# after the run succeeds
gh variable delete PAGES_BASE_URL
```

That run publishes a history containing only the new platform. Deleting the variable restores the default Pages base
URL, and subsequent runs restore normally.

For local validation:

```sh
deno task fmt
deno task lint
deno task check
deno task test
deno task bundle
```
