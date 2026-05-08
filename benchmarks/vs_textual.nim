## benchmarks/vs_textual.nim
##
## Textual comparison ratios. The spec calls for three: cold start,
## p50 latency, idle CPU. Each is `isonim_tui_value / textual_value`,
## with smaller-is-better.
##
## Status: DEFERRED. Running Textual on the bench runner requires a
## pinned Python + textual==8.x.y in `flake.nix`, plus a port of the
## standard app to a Textual `App` subclass. Both are explicitly out
## of scope for the M24 source landing — the milestone notes that the
## subprocess + Python pin land alongside the runner-image change in
## `metacraft/infra`.
##
## Until that lands, we emit the three entries with sentinel values
## (`0.0`) and an `extra: "deferred"` note so the JSON contract holds
## and downstream gh-pages tooling has stable keys.

import bench_common

proc main() =
  let opts = parseBenchOptions()

  # If a TEXTUAL_APP_PATH env var is set, in the future we'd:
  #   subprocess.run("python", "-m", "textual", "run", path)
  # capture timing, run the same workload through isonim_tui, divide.
  # For now: emit deferred placeholders.

  writeBenchFragment(opts, [
    BenchEntry(name: "vs. Textual cold start ratio",
               unit: "ratio",
               value: 0.0,
               extra: "deferred (Textual subprocess unavailable on bench runner)"),
    BenchEntry(name: "vs. Textual p50 latency ratio",
               unit: "ratio",
               value: 0.0,
               extra: "deferred (Textual subprocess unavailable on bench runner)"),
    BenchEntry(name: "vs. Textual idle CPU ratio",
               unit: "ratio",
               value: 0.0,
               extra: "deferred (Textual subprocess unavailable on bench runner)"),
  ])

main()
