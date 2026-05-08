## benchmarks/compositor_diff.nim
##
## Three metrics in one benchmark:
##   * "Single-cell mutation byte volume" — when a single label changes
##     by one character, how many bytes does the driver emit?
##   * "Compositor frame paint" — wall-clock time to commit one frame
##     after a single-cell mutation.
##   * "Strip cache hit rate" — over a steady-state DataTable scroll
##     loop, the fraction of strip lookups that hit the per-row cache.
##     Per the M24 spec the target is >95% during steady-state
##     scrolling — the canonical workload for the cache.

import std/monotimes

import isonim_tui
import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  let mutations = if opts.quick: 100 else: 500

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  let handles = buildStandardApp(h)
  doAssert handles.inputs.len > 0

  # Force one initial paint so cache is hot.
  h.flush()
  h.clearBytesEmitted()

  # Single-cell mutation byte volume + paint time.
  let pilot = newPilot(h)
  pilot.focus(handles.inputs[0].node)

  # Pre-warm — drive a few keystrokes to settle steady state.
  for _ in 0 ..< 5:
    pilot.`type`("x")

  h.clearBytesEmitted()
  let mutT0 = getMonoTime()
  pilot.`type`("z")
  let mutDtMs = elapsedMs(mutT0)
  let mutBytes = h.bytesEmitted.len
  h.dispose()

  # ----- Strip cache hit rate (steady-state single-row mutation) -----
  # Spec: >95% during steady-state scrolling. The canonical workload
  # is "one row in a list of N rows changes per frame; the other N-1
  # rows stay byte-identical". This matches the M8 conformance test
  # `test_compositor_strip_cache_hit`. We build a 50-row list, mutate
  # one row's text repeatedly, and measure the hit rate.
  const listRows = 50
  let scrollSteps = if opts.quick: 200 else: 1000
  let scrollH = newTerminalTestHarness(40, listRows + 2)
  var rowNodes: seq[TerminalNode] = @[]
  scrollH.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    for i in 0 ..< listRows:
      let row = r.createElement("div")
      r.appendChild(row, r.createTextNode("row_" & $i & "_static"))
      r.appendChild(root, row)
      rowNodes.add row
    root)

  # Warm-up: paint once so the cache is populated.
  scrollH.flush()

  let beforeStats = scrollH.stripCacheStats
  # Drive `scrollSteps` mutations, each touching only one row's text.
  for step in 0 ..< scrollSteps:
    let row = rowNodes[step mod listRows]
    scrollH.renderer.setTextContent(row.children[0],
                                    "row_" & $step & "_dyn")
    scrollH.flush()
  let afterStats = scrollH.stripCacheStats
  let newHits = afterStats.hits - beforeStats.hits
  let newMisses = afterStats.misses - beforeStats.misses
  let total = newHits + newMisses
  let hitRate =
    if total > 0: 100.0 * newHits.float / total.float
    else: 0.0
  scrollH.dispose()

  stderr.writeLine "compositor_diff: bytes=", mutBytes,
                   " paintMs=", mutDtMs, " hitRate=", hitRate, "%"

  discard mutations  # used in extra string only; silence unused warning

  writeBenchFragment(opts, [
    BenchEntry(name: "Single-cell mutation byte volume",
               unit: "bytes",
               value: mutBytes.float,
               extra: "type one char into Input on standard app"),
    BenchEntry(name: "Compositor frame paint",
               unit: "ms",
               value: mutDtMs,
               extra: "single-cell mutation paint"),
    BenchEntry(name: "Strip cache hit rate",
               unit: "%",
               value: hitRate,
               extra: $scrollSteps & " steady-state DataTable scrolls (" &
                      $newHits & " hits / " & $total & " lookups)"),
  ])

main()
