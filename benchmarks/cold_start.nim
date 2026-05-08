## benchmarks/cold_start.nim
##
## Measures "Cold start to first paint" — the wall-clock time from the
## moment we begin constructing the TerminalTestHarness to the moment
## the first compositor.paint() commits to the headless driver.
##
## Charter: real-stack only. We construct the production TerminalRenderer,
## HeadlessDriver, and Compositor, build the 30-widget standard app,
## flush once, and stop the timer.
##
## We run 30 cold starts (5 quick) and report the median in milliseconds.

import std/monotimes

import isonim_tui
import bench_common
import standard_app/app

proc oneColdStart(): float =
  let t0 = getMonoTime()
  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  discard buildStandardApp(h)
  # The mount() inside buildStandardApp does the first flush — that's
  # the "first paint". Stop the clock here.
  let dt = elapsedMs(t0)
  h.dispose()
  return dt

proc main() =
  let opts = parseBenchOptions()
  let runs = if opts.quick: 5 else: 30

  # Warm-up: one extra run before measurement so the JIT-y bits of the
  # nim runtime (lazy GC, etc.) don't bias the first sample.
  discard oneColdStart()

  var samples: seq[float] = @[]
  for i in 0 ..< runs:
    samples.add oneColdStart()

  let med = median(samples)
  stderr.writeLine "cold_start: ", runs, " samples, median=", med, " ms"

  writeBenchFragment(opts, [
    BenchEntry(name: "Cold start to first paint",
               unit: "ms",
               value: med,
               extra: "median of " & $runs & " runs, 30-widget standard app")
  ])

main()
