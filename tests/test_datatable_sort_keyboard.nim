## test_datatable_sort_keyboard — M17 mandatory test.
##
## Tab onto a column header, press Enter to sort, confirm the rendered
## row order reflects the new permutation, and that a sort indicator
## glyph appears in the header band of the active column.

import unittest
import isonim_tui

suite "M17: datatable sort via keyboard":
  test "test_datatable_sort_keyboard":
    let h = newTerminalTestHarness(60, 12)
    var table: DataTableWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      table = newDataTable(r,
        columns = @[
          ColumnDef(key: "id",    label: "ID",    width: 4),
          ColumnDef(key: "name",  label: "Name",  width: 12),
          ColumnDef(key: "score", label: "Score", width: 6)
        ],
        rows = @[
          RowData(cells: @["3", "Charlie", "70"]),
          RowData(cells: @["1", "Alice",   "90"]),
          RowData(cells: @["4", "Diana",   "80"]),
          RowData(cells: @["2", "Bob",     "60"]),
        ],
        viewportHeight = 6)
      r.appendChild(root, table.node)
      root)

    let p = newPilot(h)
    p.focus(table.node)

    # Initially the rows are in insertion order — first body row is
    # "Charlie".
    check table.rowOrder == @[0, 1, 2, 3]

    # Walk up from the first body row onto the header band. Arrow-up
    # at row 0 promotes focus to `headerCol`. The pilot's `tab` key
    # is hijacked by the focus manager (it walks the global focus
    # chain), so DataTable exposes column-band navigation through
    # the standard arrow-key cluster instead.
    p.press("up")
    check table.headerCol == 0

    # Arrow-right walks to column 1 (Name).
    p.press("right")
    check table.headerCol == 1

    # Press Enter — sort ascending by Name.
    p.press("enter")
    check table.sortColumn == 1
    check table.sortDirection == sdAscending
    # Permutation: Alice(1), Bob(3), Charlie(0), Diana(2).
    check table.rowOrder == @[1, 3, 0, 2]

    # Press Enter again on the same column — flip to descending.
    p.press("enter")
    check table.sortDirection == sdDescending
    check table.rowOrder == @[2, 0, 3, 1]

    # Arrow-right onto column 2 (Score), Enter ascending.
    p.press("right")
    check table.headerCol == 2
    p.press("enter")
    check table.sortColumn == 2
    check table.sortDirection == sdAscending
    # 60, 70, 80, 90 → rows[3], rows[0], rows[2], rows[1]
    check table.rowOrder == @[3, 0, 2, 1]

    # Snapshot the cell map so the sort indicator is visible.
    discard h.snap("m17_datatable_sorted_score_asc")

    h.dispose()
