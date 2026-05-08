## benchmarks/datatable_scroll.nim
##
## Drives a DataTable with a large dataset (10k rows in --quick mode,
## 100k rows in full) and measures:
##
##   * "DataTable scroll repaint cells" — average cells repainted per
##     scroll step (sum of dirty-region areas).
##   * "DataTable scroll FPS" — how many scroll-by-one operations
##     complete per second over the run.

import std/monotimes

import isonim_tui
import bench_common

proc main() =
  let opts = parseBenchOptions()
  let totalRows = if opts.quick: 10_000 else: 100_000
  let scrollSteps = if opts.quick: 50 else: 200
  const viewportRows = 20

  let h = newTerminalTestHarness(80, viewportRows + 4)

  var rows: seq[RowData] = @[]
  for i in 0 ..< totalRows:
    rows.add RowData(cells: @[
      $i,
      "user_" & $i,
      (if i mod 3 == 0: "Engineer" elif i mod 3 == 1: "Designer" else: "Manager"),
      $((i * 17) mod 100)
    ])

  let columns = @[
    ColumnDef(key: "id",    label: "ID",    width: 8),
    ColumnDef(key: "name",  label: "Name",  width: 16),
    ColumnDef(key: "role",  label: "Role",  width: 12),
    ColumnDef(key: "score", label: "Score", width: 6),
  ]

  var table: DataTableWidget
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    table = newDataTable(r,
                         columns = columns,
                         rows = rows,
                         viewportHeight = viewportRows)
    r.appendChild(root, table.node)
    root)

  let p = newPilot(h)
  p.focus(table.node)

  # Warm-up: 5 scrolls. The first few prime the strip cache.
  for _ in 0 ..< 5:
    p.press("down")

  # Measure: count cells repainted per scroll, and overall throughput.
  var cellsRepainted = 0
  let t0 = getMonoTime()
  for _ in 0 ..< scrollSteps:
    p.press("down")
    let regions = h.dirtyRegions
    var area = 0
    for reg in regions:
      # CellRegion is a single-row run: width cells.
      area += reg.width
    cellsRepainted += area
  let dtMs = elapsedMs(t0)

  let avgCells = cellsRepainted.float / scrollSteps.float
  let fps =
    if dtMs > 0.0: scrollSteps.float / (dtMs / 1000.0)
    else: 0.0

  stderr.writeLine "datatable_scroll: ", scrollSteps, " scrolls, ",
                   "avg cells=", avgCells, ", fps=", fps,
                   " (rows=", totalRows, ")"

  writeBenchFragment(opts, [
    BenchEntry(name: "DataTable scroll repaint cells",
               unit: "cells",
               value: avgCells,
               extra: $scrollSteps & " scrolls on " & $totalRows & "-row table"),
    BenchEntry(name: "DataTable scroll FPS",
               unit: "fps",
               value: fps,
               extra: $scrollSteps & " scrolls on " & $totalRows & "-row table"),
  ])

  h.dispose()

main()
