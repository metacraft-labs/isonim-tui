## benchmarks/snapshot.nim
##
## Measures the wall-clock time to capture the standard app's snapshot
## across all six recorded formats (plaintext, ansi, cellmap, svg,
## annotated svg, treedump). One JSON entry: median ms across
## `iterations` runs.

import std/monotimes

import isonim_tui
import isonim_tui/testing/snapshot/plaintext as snapPlain
import isonim_tui/testing/snapshot/ansi as snapAnsi
import isonim_tui/testing/snapshot/cellmap as snapCellmap
import isonim_tui/testing/snapshot/svg as snapSvg
import isonim_tui/testing/snapshot/annotated_svg as snapAnnotatedSvg
import isonim_tui/testing/snapshot/treedump as snapTreedump

import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  let iterations = if opts.quick: 20 else: 100

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  discard buildStandardApp(h)
  h.flush()

  # Warm-up: one full render of each encoder so per-call costs settle.
  discard snapPlain.encodePlaintext(h.driver.buffer)
  discard snapAnsi.encodeAnsi(h.driver.buffer)
  discard snapCellmap.encodeCellMap(h.driver.buffer)
  discard snapSvg.encodeSvg(h.driver.buffer)
  discard snapAnnotatedSvg.encodeAnnotatedSvg(h.driver.buffer, h.root,
                                              h.compositor, h.focusedId)
  discard snapTreedump.encodeTreeDump(h.compositor, h.root)

  var samples: seq[float] = @[]
  for i in 0 ..< iterations:
    let t0 = getMonoTime()
    discard snapPlain.encodePlaintext(h.driver.buffer)
    discard snapAnsi.encodeAnsi(h.driver.buffer)
    discard snapCellmap.encodeCellMap(h.driver.buffer)
    discard snapSvg.encodeSvg(h.driver.buffer)
    discard snapAnnotatedSvg.encodeAnnotatedSvg(h.driver.buffer, h.root,
                                                h.compositor, h.focusedId)
    discard snapTreedump.encodeTreeDump(h.compositor, h.root)
    samples.add elapsedMs(t0)

  let med = median(samples)
  stderr.writeLine "snapshot: iterations=", iterations,
                   " median=", med, " ms"

  writeBenchFragment(opts, [
    BenchEntry(name: "Snapshot capture (six formats)",
               unit: "ms",
               value: med,
               extra: $iterations & " iterations, all six encoders"),
  ])

  h.dispose()

main()
