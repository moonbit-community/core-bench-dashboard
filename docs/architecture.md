# Architecture

The dashboard is a static MoonBit site with a native companion binary. One module holds four packages:

```text
core_bench/     types, JSONL, row building, badge rendering   every backend
bench_parser/   the `moon bench` output parser                every backend
cmd/dashboard/  collect, update-history, update-events, status-badge   native
cmd/browser/    the Rabbita dashboard                         js
```

`core_bench` has no I/O. It is the only place that decides what a regression is, and both the browser and the
badge read it, so the site and the badge cannot disagree. `bench_parser` is separate because only the collector
parses benchmark output.

`dashboard collect` runs `moon bench` once per backend against a checked-out `moonbitlang/core` tree. It captures
one stdout and stderr log per backend, parses rendered benchmark tables, and writes newline-delimited JSON where
the first line is metadata and subsequent lines are benchmark records.

Benchmark identity is:

```text
backend + package + file + line + block_label + case_name
```

Single benchmark blocks use an empty `case_name`. Batch benchmark blocks produce one record per named timing row.

Published data lives under:

```text
data/core-bench/current/darwin-arm64/data.jsonl
data/core-bench/history/index.json
data/core-bench/history/<YYYY-MM-DD>/darwin-arm64/data.jsonl
data/core-bench/status.svg
```

The frontend loads current data and retained history directly from those static paths. It compares current records
with the immediately previous retained calendar day using `mean_us`.

Retained history holds only days that measured something. A run where `moon bench` failed for every backend leaves
`current/` carrying failure records and nothing else, and folding that into history would make it the day the next
run is compared against — every benchmark would then read `new`, because the day it should have been measured
against has no record of it. `update-history` leaves such a day out, so the next run compares against the last day
that actually measured. The failure is still reported: it is in `current/`, in the run log, and in the badge.

A day where only *some* backends failed is still folded, since it carries real numbers for the ones that ran. The
cells for a failed backend then read `new` the next day, which is the same shape of problem one column wide and is
not yet fixed.

## Regression events

A cell compares today with the previous retained day, which answers "what changed last night" and nothing else.
Leave a regression unfixed and the next day compares against the regressed value, so the cell goes quiet while the
benchmark is still slow.

`data/core-bench/events.json` is what is still outstanding. An event stores the value a benchmark broke from, so it
keeps measuring against that number long after it has aged out of the retained window — which is the point, since a
fourteen-day window cannot remember a three-week-old regression.

Opening is derived from the retained series and requires a step to survive one night: a value 5% above the running
reference opens a candidate, and it only becomes an event if the next day is still above the same reference. That
one-night confirmation is the whole noise defence, and it is why no per-benchmark statistics are needed. An event
closes when the value comes back within 5% of its baseline.

Because opening is derived, `events.json` is a persistence layer over a pure function rather than a source of
truth: delete it and the next run rebuilds whatever is still visible in the last fourteen days. Only the baselines
of older regressions are lost.

## Notes

`notes/<slug>.json`, in the repository rather than the archive, carries what a human concluded about a step — one
file per note. `update-events` folds each note onto the event it explains, so `events.json` stays a pure function
— of two inputs now, the archive and the note directory, rather than one.

One file rather than one array so the dashboard can link a reader straight at the file for a given step. The slug
is `<backend>-<label>-<opened_on>.json`, readable in a directory listing and stable while the event is open. It is
not unique by construction — two packages may share a block label — so `dashboard note` refuses to write over a
file naming a different benchmark rather than pretending the name is a key.

A note is keyed by `benchmark_id` and `opened_on` together, so it explains one episode rather than one benchmark.
A benchmark that recovers and breaks again later does not inherit an explanation written for the earlier break,
which may well have been the one that was not real. That key is stable because `update_events` lets an existing
event win over a freshly derived one, so a carried event keeps its original `opened_on` for as long as it is
outstanding.

Notes live in the repository because the archive branch is force-pushed on every run and is deliberately deletable
— see [Operations](operations.md). A judgement about a regression has to survive that, and deserves a reviewable
commit next to the reason it was made.

A note does not close an event, and that is the point: nothing disappears from the panel because someone looked at
it. The `Noted` and `Not noted` chips turn the difference into a triage backlog.

## Writing a note from the site

Each event row links into GitHub's own editor: `/new/main?filename=…&value=…` for a step with no note yet,
`/edit/main/notes/<slug>.json` for one that has. Both are plain links, and the prefilled body already carries the
`benchmark_id` and `opened_on` that are tedious to get right by hand.

They are links rather than a write path because a static page cannot hold a token and GitHub's OAuth token
endpoint does not answer cross-origin requests, so writing through the page would need a server behind it. That
would invert the property this whole design rests on: nothing reads the published site back, so the site is a pure
output. GitHub owns the sign-in, the editor, the commit and the history instead, and a reader without push access
gets the fork-and-pull-request path for free.

Committing under `notes/` on `main` triggers a run, so a note written this way is published without anyone
dispatching a workflow. That trigger is the only one besides the schedule and a manual dispatch.

Today there is still no second way to close an event. An accepted regression — one nobody intends to fix — stays
in the panel until the number moves. Manual acknowledgement remains the intended answer, and is now a note that
also accepts a level rather than a separate mechanism. It is not built yet.

## The archive is not the served copy

Two stores, deliberately separate:

```text
bench-data branch    the archive — what the next run reads
GitHub Pages         the served copy — what a browser reads
```

Each run clones `bench-data`, folds the new day in, prunes to fourteen, and force-pushes the same tree back as an
orphan commit. The identical tree is then deployed to Pages. Nothing ever reads the published site back, so the
site is a pure output and a failed deploy cannot corrupt the history.

The branch is force-pushed rather than accumulated: a day is about 1.2 MB of JSONL and logs that diff badly, so
keeping every commit would add roughly 440 MB a year for an audit trail the run logs already provide. One tree
deep keeps the repository bounded at about 17 MB.

Because the archive is the whole `data/` tree — current day, retained history, and `status.svg` — the branch is
exactly what was deployed, and any past deploy can be reproduced from it.

## Serialization

Record and metadata types are serialized with [`Yu-zh/data`](https://github.com/Yu-zh/data). Three of its
properties matter here:

- `#data.rename` keeps the published camelCase metadata field names next to snake_case MoonBit fields.
- Unknown fields are skipped rather than rejected, so a schema change does not break the fourteen days of
  already-published history the next run restores.
- An absent field and an explicit `null` both read back as `None`.

Implementations are generated, not written. After changing a type in `core_bench/types.mbt`, re-run:

```sh
moonx Yu-zh/data/derive core_bench
```

and commit the regenerated `core_bench/types_derive.mbt`.

## Ordering

`String::compare` in MoonBit orders by length before content. Every ordering the dashboard shows — history dates,
package and file names, benchmark labels — uses `String::lexical_compare` instead, so rows sort the way a reader
expects to read them.
