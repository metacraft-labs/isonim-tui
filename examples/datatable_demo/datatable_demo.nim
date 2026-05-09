## examples/datatable_demo/datatable_demo.nim — M27 demo: a 1000-row
## DataTable showing the M17 virtualisation in action.
##
## The DataTable widget only paints the visible viewport so a 1000-row
## dataset stays cheap to scroll. The benchmark
## `tests/test_datatable_virtualisation_perf.nim` proves this. Here we
## use the same widget surface with deterministic synthetic data so a
## snapshot test can land a stable golden.

import isonim_tui

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
  let root = r.createElement("div")
  r.setAttribute(root, "class", "datatable-demo")

  let header = newHeader(r, title = "DataTable Demo",
                         subtitle = "1000 rows, virtualised",
                         width = h.cols)
  r.appendChild(root, header.node)

  let columns = @[
    ColumnDef(key: "id",     label: "id",     width: 5),
    ColumnDef(key: "name",   label: "name",   width: 12),
    ColumnDef(key: "amount", label: "amount", width: 8)]

  let rows = generateRows(1000)
  let dt = newDataTable(r, columns = columns, rows = rows,
                        viewportHeight = max(5, h.rows - 4),
                        border = bsSolid)
  r.appendChild(root, dt.node)

  root

proc mountDataTableDemo*(h: TerminalTestHarness) =
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildDataTableDemoApp(h))

when isMainModule:
  let h = newTerminalTestHarness(40, 18)
  mountDataTableDemo(h)
  echo "DataTable demo mounted with 1000 rows."
  h.dispose()
