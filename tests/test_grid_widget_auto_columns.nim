## test_grid_widget_auto_columns
##
## End-to-end exercise of `auto`-track intrinsic measurement at the
## Container widget level. Mounts a Container with
## `grid-columns: auto auto`, attaches two Statics with different
## natural widths, and asserts each child occupies the column matching
## its measured content width — not a 1-cell stub, not a 1fr fill.

import unittest
import isonim_tui

suite "M5 grid: auto-column intrinsic measurement (widget)":

  test "test_auto_auto_columns_size_to_each_child":
    let h = newTerminalTestHarness(40, 4)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 30, viewportHeight = 2,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 2, rows: 1),
        columns: @[GridTrack(kind: gtkAuto, value: 1.0),
                   GridTrack(kind: gtkAuto, value: 1.0)],
        rows: @[GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      let a = newStatic(r, "AA", width = cellWidth("AA"), height = 1)
      let b = newStatic(r, "BBBBBB", width = cellWidth("BBBBBB"), height = 1)
      container.append(a.node)
      container.append(b.node)
      r.appendChild(root, container.node)
      root)

    # Each auto column resolves to its child's natural width.
    check container.gridRects.len == 2
    check container.gridRects[0].col == 0
    check container.gridRects[0].width == 2
    check container.gridRects[1].col == 2
    check container.gridRects[1].width == 6

    h.dispose()

  test "test_auto_then_fr_fills_remainder":
    # `grid-columns: auto 1fr` — the auto column shrinks to its child's
    # natural width and the fr column eats the rest of the inner width.
    let h = newTerminalTestHarness(40, 4)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 2,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 2, rows: 1),
        columns: @[GridTrack(kind: gtkAuto, value: 1.0),
                   GridTrack(kind: gtkFr, value: 1.0)],
        rows: @[GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      let label = newStatic(r, "Name:", width = cellWidth("Name:"), height = 1)
      let value = newStatic(r, "x", width = cellWidth("x"), height = 1)
      container.append(label.node)
      container.append(value.node)
      r.appendChild(root, container.node)
      root)

    check container.gridRects[0].width == 5     # cellWidth("Name:")
    check container.gridRects[1].col == 5
    check container.gridRects[1].width == 15    # 20 - 5 = remainder

    h.dispose()

  test "test_spanning_child_grows_both_auto_columns":
    # Two auto columns. Row 0 carries one child spanning both columns;
    # row 1 carries two narrow children. Both auto columns must grow to
    # accommodate the spanning child's natural width.
    let h = newTerminalTestHarness(40, 6)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 30, viewportHeight = 4,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 2, rows: 2),
        columns: @[GridTrack(kind: gtkAuto, value: 1.0),
                   GridTrack(kind: gtkAuto, value: 1.0)],
        rows: @[GridTrack(kind: gtkFr, value: 1.0),
                GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      let big = newStatic(r, "0123456789",
                          width = cellWidth("0123456789"), height = 1)
      let small1 = newStatic(r, "AA", width = cellWidth("AA"), height = 1)
      let small2 = newStatic(r, "BB", width = cellWidth("BB"), height = 1)
      container.append(big.node)
      container.setChildSpan(0, colSpan = 2, rowSpan = 1)
      container.append(small1.node)
      container.append(small2.node)
      r.appendChild(root, container.node)
      root)

    # First-pass: col 0 = 2, col 1 = 2 (max single-track natural widths).
    # Span deficit: 10 - 4 = 6, distributed evenly → +3 to each.
    # Final: col 0 width = 5, col 1 width = 5; spanning child = 10.
    check container.gridRects[0].width == 10
    check container.gridRects[0].col == 0
    check container.gridRects[1].col == 0
    check container.gridRects[1].width == 5
    check container.gridRects[2].col == 5
    check container.gridRects[2].width == 5

    h.dispose()
