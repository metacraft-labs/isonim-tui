## test_datatable_selection — M17 mandatory test.
##
## A focused DataTable; arrow-down moves the cursor; the bound
## selection callback fires with the new row index; the cell-map
## snapshot reflects the highlighted row.

import unittest
import isonim_tui

suite "M17: datatable selection":
  test "test_datatable_selection":
    let h = newTerminalTestHarness(50, 10)
    var table: DataTableWidget
    var lastChange: tuple[oldRow, newRow, oldCol, newCol: int] =
      (-9, -9, -9, -9)
    var lastActivated: tuple[row, col: int] = (-9, -9)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      table = newDataTable(r,
        columns = @[
          ColumnDef(key: "id",   label: "ID",   width: 4),
          ColumnDef(key: "name", label: "Name", width: 12)
        ],
        rows = @[
          RowData(cells: @["1", "Alice"]),
          RowData(cells: @["2", "Bob"]),
          RowData(cells: @["3", "Carol"]),
          RowData(cells: @["4", "Dave"]),
        ],
        viewportHeight = 5,
        onSelectionChange = proc(o, n, oc, nc: int) =
          lastChange = (o, n, oc, nc),
        onActivate = proc(row, col: int) =
          lastActivated = (row, col))
      r.appendChild(root, table.node)
      root)

    let p = newPilot(h)
    p.focus(table.node)

    # Initial selection: row 0, col 0.
    check table.selectedRow == 0
    check table.selectedCol == 0

    # Arrow-down moves selection to row 1.
    p.press("down")
    check table.selectedRow == 1
    check table.selectedCol == 0
    check lastChange.oldRow == 0
    check lastChange.newRow == 1

    # Arrow-down again to row 2.
    p.press("down")
    check table.selectedRow == 2
    check lastChange.newRow == 2

    # Arrow-right to col 1.
    p.press("right")
    check table.selectedCol == 1
    check lastChange.newCol == 1

    # End jumps to last row.
    p.press("end")
    check table.selectedRow == 3

    # Home jumps back to first row.
    p.press("home")
    check table.selectedRow == 0

    # Enter activates.
    p.press("enter")
    check lastActivated.row == 0
    check lastActivated.col == 1

    # Snapshot the cell-map: highlighted row should be visible.
    discard h.snap("m17_datatable_selection")

    h.dispose()
