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
5. Clone the `bench-data` archive, add or replace the current day, prune to 14 days, update the regression
   events, generate `status.svg`, force-push the archive back, build the browser bundle with `warren`, and deploy
   the static site to GitHub Pages.

The badge is red if any current cell is a 5% or larger regression versus the previous retained day, or if a backend
benchmark command failed. It is green otherwise. It does not yet reflect outstanding regression events, which are
shown in their own panel on the site — see [Architecture](architecture.md).

## Rebuilding the site without re-benchmarking

A frontend change, or a change to how events or the badge are computed, does not need new measurements. Dispatch
the workflow with `mode: publish-only`:

```sh
gh workflow run core-bench.yml -f mode=publish-only
```

`collect-data` is skipped entirely, so the bench box is untouched and the run takes about two minutes instead of
twenty-eight. `publish-site` reads `current/` and `history/` from the archive, regenerates `events.json` and
`status.svg`, rebuilds the browser bundle, and deploys. That works because the archive carries the whole `data/`
tree, current day included, not just retained history.

`update-history` also declines to fold a day on which nothing was measured — see
[Architecture](architecture.md) — so a run where `moon bench` failed on every backend reports the failure without
becoming the baseline for the next one.

**`update-history` never runs in publish-only mode**, and that guard is the reason the mode is safe. It folds `current/`
into history under *today's* date; in publish-only mode `current/` is whatever the archive already holds, so
running it would write a history day out of an older run's numbers — and that fabricated day then becomes the
baseline the next real run is compared against. The condition sits on the step itself so it stays visible.

Scheduled runs always collect: `inputs.mode` is null outside a manual dispatch, which is not `publish-only`.

## Noting a regression

Concluding something about an outstanding regression — that it is real and upstream, that it is measurement noise,
that someone is already fixing it — is worth recording where the next reader will find it.

```sh
./dashboard note --backend native --match "rev_find adversary m=64 n=4096" \
  --text "Not reproducible as a toolchain regression: identical generated C and hot assembly, 7.313us and 7.345us. Suspected measurement contamination in moon bench."
```

The dashboard also links at this directly: every event row carries an **Add note** or **Edit note** link into
GitHub's editor, with `benchmark_id` and `opened_on` already filled in. Committing there publishes the note
without any of the steps below. The command is for when you are already in a terminal.

`--match` is a fragment of the benchmark label, package, or file, resolved against the current `events.json`. The
command fails rather than guessing when it matches nothing or more than one benchmark; `--backend` narrows it,
since the same label usually exists on all four. Everything else — the benchmark id, the step the note belongs to,
the date — is filled in from the event, because the id is sixty characters of pipe-separated identity that a
mistyped copy would silently fail to match.

Notes live one per file under `notes/`, named `<backend>-<label>-<opened_on>.json`. Writing twice about the same
step replaces the file; removing a note is deleting it.

Then commit the note:

```sh
git add notes && git commit -m "Note the rev_find adversary regression"
git push
```

A push to `main` touching `notes/**` runs the workflow on its own, and `collect-data` is skipped for a push, so
publishing a note costs about two minutes and leaves the bench box alone. Nothing else in the repository triggers
a run: a code change still goes out by dispatch.

`notes/` sits at the repository root, which is where `publish-site` runs, so CI needs no argument for it.
`update-events` prints how many notes found a step: a note whose event has since closed matches nothing and is
counted out, so an explanation that has gone stale shows in the run log rather than rotting quietly. A malformed
note file fails the run instead of publishing with it silently dropped.

A note does not remove a regression from the panel. It marks it as looked at, which is what the panel's `Noted`
and `Not noted` chips then count.

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

Before trusting a frontend change, serve it **under a path**, not at a server root. The published site lives at
`/core-bench-dashboard/`, and `@http.get` resolves relative paths against the origin rather than the document, so
a data path that works at a root can still 404 in production:

```sh
warren build --server-entry ""
mkdir -p /tmp/check/core-bench-dashboard
cp dist/index.html dist/index.js /tmp/check/core-bench-dashboard/
cp -r data /tmp/check/core-bench-dashboard/
(cd /tmp/check && python3 -m http.server 8733)
# then open http://127.0.0.1:8733/core-bench-dashboard/
```
