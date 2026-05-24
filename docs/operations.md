# Operations

CI performs four phases:

1. Install Deno and the nightly MoonBit toolchain.
2. Clone `https://github.com/moonbitlang/core` at `main`.
3. Run `moon bench --target <backend> --target-dir <tmp/build> --frozen --no-parallelize` for `wasm`, `wasm-gc`, `js`,
   and `native`.
4. Restore published history, add or replace the current day, prune to 14 days, generate `status.svg`, bundle `web.ts`,
   and deploy the static site to GitHub Pages.

The badge is red if any current cell is a 5% or larger regression versus the previous retained day, or if a backend
benchmark command failed. It is green otherwise.

For local validation:

```sh
deno task fmt
deno task lint
deno task check
deno task test
deno task bundle
```
