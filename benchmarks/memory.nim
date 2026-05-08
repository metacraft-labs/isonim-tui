## benchmarks/memory.nim
##
## Two metrics:
##   * "RSS at idle (standard app)" — resident set size in MB after
##     the standard app has settled.
##   * "RSS per added widget" — incremental RSS per added Static widget,
##     in KB amortised over a batch.

import isonim_tui
import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  # The amortised KB-per-widget figure converges as the count grows;
  # short runs are dominated by allocator chunking. Use 1k for quick
  # CI, 10k for full runs.
  let extraWidgets = if opts.quick: 1000 else: 10_000

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  let handles = buildStandardApp(h)
  h.flush()

  # Settle GC: force one cycle so we measure live state, not detritus.
  GC_fullCollect()

  let baseRss = rssKb()
  let baseMb = baseRss.float / 1024.0

  # Add `extraWidgets` text nodes and measure delta. The "added
  # widget" baseline is intentionally a plain text node (the smallest
  # mountable atom in the renderer tree) — that's what the Textual /
  # IsoNim performance tier compares against. Composite widgets like
  # DataTable carry per-instance Table overhead that's not the
  # "incremental widget cost" the spec is asking about.
  let r = h.renderer
  for i in 0 ..< extraWidgets:
    let txt = r.createTextNode("L" & $i)
    r.appendChild(handles.root, txt)
  h.flush()
  GC_fullCollect()

  let afterRss = rssKb()
  let deltaKb = (afterRss - baseRss).float / extraWidgets.float
  let perWidgetKb = max(0.0, deltaKb)

  stderr.writeLine "memory: idleMb=", baseMb,
                   " perWidgetKb=", perWidgetKb,
                   " (added ", extraWidgets, " widgets)"

  writeBenchFragment(opts, [
    BenchEntry(name: "RSS at idle (standard app)",
               unit: "MB",
               value: baseMb,
               extra: "30-widget standard app, post first paint"),
    BenchEntry(name: "RSS per added widget",
               unit: "KB",
               value: perWidgetKb,
               extra: "amortised over " & $extraWidgets & " Static widgets"),
  ])

  h.dispose()

main()
