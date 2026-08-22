# Operations

## Runners

`collect-data` runs on a self-hosted Apple Silicon macOS runner carrying the `self-hosted` and `bench-box` labels.
`publish-site` stays on `ubuntu-latest`, so a deploy never waits on the bench machine.

Because a self-hosted workspace persists between runs, `collect-data` starts by removing `core`, `data`, `_build`,
`.mooncakes`, `dist`, and the previous binary. The runner needs `git`, `curl`, and Xcode Command Line Tools; both
MoonBit toolchains are installed per run.

## Two toolchains, on purpose

The dashboard measures the nightly toolchain, so nightly must not build it. If one binary were built by the
compiler under test, a nightly regression would take out the measurement and the instrument together, and a red
badge could no longer be read as a statement about `moonbitlang/core`.

CI therefore installs stable into its own `MOON_HOME`:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | MOON_HOME="$HOME/.moon-stable" bash
MOON_HOME="$HOME/.moon-stable" PATH="$HOME/.moon-stable/bin:$PATH" moon build --target native --release
```

Nightly is installed afterwards and is the only toolchain on `PATH` when `dashboard collect` spawns `moon bench`.
`MOON_HOME` is never exported into the collect step, or the nightly `moon` would find the stable core library.
`MOONC_RC_CONVENTION` is scoped to the collect step for the same reason.

## Phases

CI performs five phases:

1. Install the stable toolchain and build the `dashboard` binary.
2. Install the nightly MoonBit toolchain.
3. Clone `https://github.com/moonbitlang/core` at `main`.
4. Run `moon bench --target <backend> --target-dir <tmp/build> --frozen --no-parallelize` for `wasm`, `wasm-gc`,
   `js`, and `native`.
5. Restore published history, add or replace the current day, prune to 14 days, generate `status.svg`, build the
   browser bundle with `warren`, and deploy the static site to GitHub Pages.

The badge is red if any current cell is a 5% or larger regression versus the previous retained day, or if a backend
benchmark command failed. It is green otherwise.

## Changing the benchmark platform

`DASHBOARD_OS` in `core_bench/types.mbt` names the single platform the dashboard publishes. Retained history is
keyed by date only, so history collected on a different platform must not be carried across a change of that
constant: the regenerated index would point at paths that do not exist for older days, and every benchmark would
silently read as `new`.

To break the chain, point the restore at a URL that does not resolve for exactly one run.
`restore_published_history` returns early when the history index cannot be fetched, so nothing is restored and no
workflow edit is needed:

```sh
gh variable set PAGES_BASE_URL --body 'https://invalid.invalid'
gh workflow run core-bench.yml
# after the run succeeds
gh variable delete PAGES_BASE_URL
```

That run publishes a history containing only the new platform. Deleting the variable restores the default Pages base
URL, and subsequent runs restore normally.

## Local validation

```sh
moon fmt
moon check --target all
moon test --target all
moon build --target native --release
warren build --server-entry ""
```

To see the site against real published data:

```sh
./dashboard restore-history https://moonbit-community.github.io/core-bench-dashboard
warren dev --server-entry ""
```
