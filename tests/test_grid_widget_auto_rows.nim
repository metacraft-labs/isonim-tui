## test_grid_widget_auto_rows
##
## End-to-end exercise of `auto`-track intrinsic measurement on the row
## axis. Mounts a Container with `grid-rows: auto auto`, attaches two
## Statics with different natural heights, and asserts each child
## occupies the row matching its measured content height.

import unittest
import isonim_tui

suite "M5 grid: auto-row intrinsic measurement (widget)":

  test "test_auto_auto_rows_size_to_each_child":
    let h = newTerminalTestHarness(40, 12)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 8,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 1, rows: 2),
        columns: @[GridTrack(kind: gtkFr, value: 1.0)],
        rows: @[GridTrack(kind: gtkAuto, value: 1.0),
                GridTrack(kind: gtkAuto, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      # Three-row child, then a one-row child. The container is a
      # 1-column grid so they stack vertically across the two auto
      # rows.
      let multi = newStatic(r, "AAA\nBBB\nCCC",
                            width = 3, height = 3)
      let single = newStatic(r, "X", width = 1, height = 1)
      container.append(multi.node)
      container.append(single.node)
      r.appendChild(root, container.node)
      root)

    check container.gridRects.len == 2
    check container.gridRects[0].row == 0
    check container.gridRects[0].height == 3
    check container.gridRects[1].row == 3
    check container.gridRects[1].height == 1

    h.dispose()

  test "test_auto_then_fr_row_fills_remaining_height":
    let h = newTerminalTestHarness(40, 12)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 10,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 1, rows: 2),
        columns: @[GridTrack(kind: gtkFr, value: 1.0)],
        rows: @[GridTrack(kind: gtkAuto, value: 1.0),
                GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      let header = newStatic(r, "HDR\nLINE2", width = 5, height = 2)
      let body = newStatic(r, "body", width = 4, height = 1)
      container.append(header.node)
      container.append(body.node)
      r.appendChild(root, container.node)
      root)

    # Auto row sizes to its child's natural height (2 rows). Fr row
    # absorbs the remaining 8 cells.
    check container.gridRects[0].height == 2
    check container.gridRects[1].row == 2
    check container.gridRects[1].height == 8

    h.dispose()
