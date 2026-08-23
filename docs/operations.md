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
5. Clone the `bench-data` archive, add or replace the current day, prune to 14 days, generate `status.svg`,
   force-push the archive back, build the browser bundle with `warren`, and deploy the static site to GitHub
   Pages.

The badge is red if any current cell is a 5% or larger regression versus the previous retained day, or if a backend
benchmark command failed. It is green otherwise.

## The benchmark archive

Retained history lives on the `bench-data` branch, not in the published site. Each run clones it, folds the day in,
and force-pushes the whole `data/` tree back as a single orphan commit; the same tree is then deployed to Pages.

The workflow needs `contents: write` for that push, and a `concurrency` group so two runs cannot race the
force-push. A missing branch is not an error — the run starts a fresh archive and says so in the log.

The archive is the only copy of retained history. It is replicated by GitHub and by every clone, and a bad day can
be undone by resetting the branch, but nothing reconstructs it from source.

## Changing the benchmark platform

`DASHBOARD_OS` in `core_bench/types.mbt` names the single platform the dashboard publishes. Retained history is
keyed by date only, so history collected on a different platform must not be carried across a change of that
constant: the regenerated index would point at paths that do not exist for older days, and every benchmark would
silently read as `new`.

To break the chain, delete the archive and let the next run start a new one:

```sh
git push --delete origin bench-data
gh workflow run core-bench.yml
```

That run publishes a history containing only the new platform. Take a copy of the branch first if the old data is
worth keeping — deleting it is the only way to lose it.

## Local validation

```sh
moon fmt
moon check --target all
moon test --target all
moon build --target native --release
warren build --server-entry ""
```

To see the site against real data:

```sh
git clone --branch bench-data --single-branch --depth 1 \
  https://github.com/moonbit-community/core-bench-dashboard.git data
warren dev --server-entry ""
```
