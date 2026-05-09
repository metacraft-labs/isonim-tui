## examples/datatable_demo/datatable_demo.nim — M27 demo: a 1000-row
## DataTable showing the M17 virtualisation in action.
##
## The DataTable widget only paints the visible viewport so a 1000-row
## dataset stays cheap to scroll. The benchmark
## `tests/test_datatable_virtualisation_perf.nim` proves this. Here we
## use the same widget surface with deterministic synthetic data so a
## snapshot test can land a stable golden.
##
## DM-M2: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Structural divs use `tdiv(class=...)`,
## widgets compose via the `w*` wrappers in
## `isonim_tui/dsl/widget_blocks`.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

# ----------------------------------------------------------------------------
# Deterministic dataset
# ----------------------------------------------------------------------------

proc generateRows*(count: int): seq[RowData] =
  ## A 1000-row dataset. Each row's "name" cycles through a small
  ## list, the "amount" follows a deterministic LCG.
  const Names = ["alpha", "beta", "gamma", "delta", "epsilon",
                 "zeta", "eta", "theta", "iota", "kappa"]
  result = newSeqOfCap[RowData](count)
  var s: uint64 = 0xC0FFEE
  for i in 0 ..< count:
    s = s * 6364136223846793005'u64 + 1442695040888963407'u64
    let amount = int((s shr 40) and 0xFFFF)
    let name = Names[i mod Names.len]
    result.add RowData(cells: @[$i, name, $amount])

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildDataTableDemoApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let cols = h.cols
  let columns = @[
    ColumnDef(key: "id",     label: "id",     width: 5),
    ColumnDef(key: "name",   label: "name",   width: 12),
    ColumnDef(key: "amount", label: "amount", width: 8)]
  let rows = generateRows(1000)
  let viewport = max(5, h.rows - 4)

  result = ui(r):
    tdiv(class = "datatable-demo"):
      wHeader(r, "DataTable Demo", "1000 rows, virtualised", cols)
      wDataTable(r, columns, rows, viewport, bsSolid)

proc mountDataTableDemo*(h: TerminalTestHarness) =
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildDataTableDemoApp(h))

when isMainModule:
  let h = newTerminalTestHarness(40, 18)
  mountDataTableDemo(h)
  echo "DataTable demo mounted with 1000 rows."
  h.dispose()
