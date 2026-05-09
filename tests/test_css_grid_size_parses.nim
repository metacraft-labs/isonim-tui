## test_css_grid_size_parses
##
## M5 grid-property closure: the typed grid surface (`grid-size`,
## `grid-rows`, `grid-columns`, `grid-gutter`, `column-span`, `row-span`)
## flows through the real tokenizer, parser, and cascade onto the
## `Styles` object.

import unittest
import isonim_tui

suite "M5 grid: typed property parsing":

  test "test_grid_size_two_args":
    let r = TerminalRenderer()
    let n = r.createElement("Container")
    r.setAttribute(n, "id", "g")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Container {
        layout: grid;
        grid-size: 3 2;
        grid-gutter: 1 1;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.layout == lkGrid
    check computed.gridSizeSet
    check computed.gridSize.cols == 3
    check computed.gridSize.rows == 2
    check computed.gridGutterSet
    check computed.gridGutter.horizontal == 1
    check computed.gridGutter.vertical == 1

  test "test_grid_size_cols_only_means_unbounded_rows":
    let r = TerminalRenderer()
    let n = r.createElement("Container")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Container { grid-size: 4; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.gridSizeSet
    check computed.gridSize.cols == 4
    # rows == 0 is the "unbounded — auto-flow" sentinel.
    check computed.gridSize.rows == 0

  test "test_grid_tracks_mixed_kinds":
    let r = TerminalRenderer()
    let n = r.createElement("Container")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Container {
        grid-columns: 1fr 2fr auto 30%;
        grid-rows: 5 1fr;
        grid-gutter: 2;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.gridColumnsSet
    check computed.gridColumns.len == 4
    check computed.gridColumns[0].kind == gtkFr
    check computed.gridColumns[0].value == 1.0
    check computed.gridColumns[1].kind == gtkFr
    check computed.gridColumns[1].value == 2.0
    check computed.gridColumns[2].kind == gtkAuto
    check computed.gridColumns[3].kind == gtkPercent
    check computed.gridColumns[3].value == 30.0

    check computed.gridRowsSet
    check computed.gridRows.len == 2
    check computed.gridRows[0].kind == gtkFixed
    check computed.gridRows[0].value == 5.0
    check computed.gridRows[1].kind == gtkFr

    # Single-value grid-gutter mirrors to both axes.
    check computed.gridGutterSet
    check computed.gridGutter.horizontal == 2
    check computed.gridGutter.vertical == 2

  test "test_column_row_span_per_child":
    let r = TerminalRenderer()
    let n = r.createElement("Static")
    r.setAttribute(n, "class", "wide")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      .wide {
        column-span: 2;
        row-span: 3;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.columnSpanSet
    check computed.columnSpan == 2
    check computed.rowSpanSet
    check computed.rowSpan == 3
