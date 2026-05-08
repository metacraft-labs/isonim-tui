## examples/ports/data_table_row_labels.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/data_table_row_labels.py`
## (M23 compat suite).
##
## Original (Python):
##
##   ROWS = [
##       ("lane", "swimmer", "country", "time"),
##       (5, "Chad le Clos", "South Africa", 51.14),
##       (4, "Joseph Schooling", "Singapore", 50.39),
##       ...
##   ]
##   class TableApp(App):
##       def compose(self): yield DataTable()
##       def on_mount(self):
##           table = self.query_one(DataTable)
##           table.fixed_rows = 1
##           table.fixed_columns = 1
##           table.focus()
##           rows = iter(ROWS)
##           column_labels = next(rows)
##           for column in column_labels: table.add_column(column, key=column)
##           for index, row in enumerate(rows):
##               table.add_row(*row, label=str(index))
##
## A 4-column DataTable with row-label index. The M17 DataTable widget
## supports column definitions and string row cells — we render the
## row label as a synthetic prepended column so the cell-content
## matches the Textual frame.

import isonim_tui

proc buildDataTableRowLabelsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let columns = @[
    ColumnDef(key: "idx",     label: "",         width: 3),
    ColumnDef(key: "lane",    label: "lane",     width: 5),
    ColumnDef(key: "swimmer", label: "swimmer",  width: 22),
    ColumnDef(key: "country", label: "country",  width: 16),
    ColumnDef(key: "time",    label: "time",     width: 6),
  ]

  # The Python original passes the lane as an int but the widget
  # renders it via `str()`; emulate by stringifying upfront.
  let raw = @[
    @["5",  "Chad le Clos",         "South Africa",  "51.14"],
    @["4",  "Joseph Schooling",     "Singapore",     "50.39"],
    @["2",  "Michael Phelps",       "United States", "51.14"],
    @["6",  "László Cseh",          "Hungary",       "51.14"],
    @["3",  "Li Zhuhao",            "China",         "51.26"],
    @["8",  "Mehdy Metella",        "France",        "51.58"],
    @["7",  "Tom Shields",          "United States", "51.73"],
    @["10", "Darren Burns",         "Scotland",      "51.84"],
    @["1",  "Aleksandr Sadovnikov", "Russia",        "51.84"],
  ]

  var rows: seq[RowData] = @[]
  for idx, row in raw:
    rows.add RowData(cells: @[$idx, row[0], row[1], row[2], row[3]])

  let dt = newDataTable(r, columns = columns, rows = rows,
                        viewportHeight = max(rows.len + 1, 10),
                        border = bsSolid)
  r.appendChild(root, dt.node)

  # Mirror `table.focus()` so the snapshot picks up the focused border.
  let p = newPilot(h)
  p.focus(dt.node)

  root
