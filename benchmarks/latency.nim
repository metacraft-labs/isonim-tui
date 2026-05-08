## benchmarks/latency.nim
##
## Input latency: how long from a synthetic key event arriving at the
## focused widget to the next compositor.paint completing. We drive the
## standard app's first form input via the harness Pilot and measure
## the round-trip per keystroke.
##
## Reports both p50 and p99 in milliseconds.

import std/monotimes

import isonim_tui
import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  let keystrokes = if opts.quick: 200 else: 1000

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  let handles = buildStandardApp(h)
  doAssert handles.inputs.len > 0

  # Focus the first input and pre-warm so the cache is hot.
  let pilot = newPilot(h)
  pilot.focus(handles.inputs[0].node)

  # Pre-warm: 50 keystrokes that are not measured.
  for _ in 0 ..< 50:
    pilot.`type`("x")

  var samples: seq[float] = @[]
  for i in 0 ..< keystrokes:
    let t0 = getMonoTime()
    # Single keystroke through the full pipeline:
    # pilot → handler → renderer state mutation → flush → paint → driver.
    pilot.`type`("a")
    samples.add elapsedMs(t0)

  let p50 = percentile(samples, 0.5)
  let p99 = percentile(samples, 0.99)
  stderr.writeLine "latency: ", samples.len, " samples, p50=", p50,
                   " ms, p99=", p99, " ms"

  writeBenchFragment(opts, [
    BenchEntry(name: "Input latency p50", unit: "ms", value: p50,
               extra: $samples.len & " keystrokes typed into Input widget"),
    BenchEntry(name: "Input latency p99", unit: "ms", value: p99,
               extra: $samples.len & " keystrokes typed into Input widget"),
  ])

  h.dispose()

main()
