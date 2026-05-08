## test_datatable_snapshot_coverage — M17 snapshot deliverable.
##
## Five fixtures: empty / 100 rows / scrolled to row 50 / sorted-by-column /
## row-selected. The 100-row dataset comes from
## `tests/fixtures/datatable_users.json` so the goldens are stable
## across runs.

import std/[json, os]
import unittest
import isonim_tui

proc loadFixture(): tuple[columns: seq[ColumnDef]; rows: seq[RowData]] =
  let path = currentSourcePath().parentDir / "fixtures" / "datatable_users.json"
  let data = parseJson(readFile(path))
  var cols: seq[ColumnDef] = @[]
  for c in data["columns"]:
    cols.add ColumnDef(
      key: c["key"].getStr,
      label: c["label"].getStr,
      width: c["width"].getInt)
  var rs: seq[RowData] = @[]
  for r in data["rows"]:
    rs.add RowData(cells: @[
      r["id"].getStr,
      r["name"].getStr,
      r["role"].getStr,
      r["score"].getStr
    ])
  (cols, rs)

suite "M17: datatable snapshot coverage":

  test "datatable_empty":
    let h = newTerminalTestHarness(50, 8)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let dt = newDataTable(r,
        columns = @[
          ColumnDef(key: "id",   label: "ID",   width: 4),
          ColumnDef(key: "name", label: "Name", width: 12)
        ],
        rows = @[],
        viewportHeight = 5)
      r.appendChild(root, dt.node)
      root)
    discard h.snap("m17_datatable_empty")
    h.dispose()

  test "datatable_100_rows_default":
    let (cols, rows) = loadFixture()
    let h = newTerminalTestHarness(60, 12)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let dt = newDataTable(r,
        columns = cols, rows = rows,
        viewportHeight = 8)
      r.appendChild(root, dt.node)
      root)
    discard h.snap("m17_datatable_100_default")
    h.dispose()

  test "datatable_100_scrolled_to_row_50":
    let (cols, rows) = loadFixture()
    let h = newTerminalTestHarness(60, 12)
    var dt: DataTableWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      dt = newDataTable(r,
        columns = cols, rows = rows,
        viewportHeight = 8)
      r.appendChild(root, dt.node)
      root)
    let p = newPilot(h)
    p.focus(dt.node)
    # Move the selection (and viewport) down to row 50.
    for _ in 0 ..< 50:
      p.press("down")
    discard h.snap("m17_datatable_scrolled_to_50")
    h.dispose()

  test "datatable_sorted_by_score":
    let (cols, rows) = loadFixture()
    let h = newTerminalTestHarness(60, 12)
    var dt: DataTableWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      dt = newDataTable(r,
        columns = cols, rows = rows,
        viewportHeight = 8)
      r.appendChild(root, dt.node)
      root)
    dt.sortByColumn(3, sdAscending)
    h.flush()
    discard h.snap("m17_datatable_sorted_by_score")
    h.dispose()

  test "datatable_row_selected":
    let (cols, rows) = loadFixture()
    let h = newTerminalTestHarness(60, 12)
    var dt: DataTableWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      dt = newDataTable(r,
        columns = cols, rows = rows,
        viewportHeight = 8)
      r.appendChild(root, dt.node)
      root)
    let p = newPilot(h)
    p.focus(dt.node)
    # Select row 3.
    p.press("down", "down", "down")
    discard h.snap("m17_datatable_row_selected")
    h.dispose()
