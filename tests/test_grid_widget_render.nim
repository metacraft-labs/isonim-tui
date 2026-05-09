## test_grid_widget_render
##
## Mounts a Container with `layout: clGrid` plus 4 Static children and
## asserts the rendered cells reflect the computed grid positions.
## Drives the real renderer + compositor through `TerminalTestHarness`.

import unittest
import std/unicode
import isonim_tui

suite "M5 grid: widget render":

  test "test_two_by_two_grid_widget":
    let h = newTerminalTestHarness(40, 6)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 4,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 2, rows: 2),
        columns: @[GridTrack(kind: gtkFr, value: 1.0),
                   GridTrack(kind: gtkFr, value: 1.0)],
        rows: @[GridTrack(kind: gtkFr, value: 1.0),
                GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 0, vertical: 0)))
      # Each cell is 10 cells wide, 2 rows tall.
      for label in ["AAAA", "BBBB", "CCCC", "DDDD"]:
        let s = newStatic(r, label, width = cellWidth(label), height = 1)
        container.append(s.node)
      r.appendChild(root, container.node)
      root)

    # Verify the placement metadata. `gridRects` carries cell
    # coordinates (post-resolver), so row is in *cells*. Each row track
    # is `viewport / 2 = 2` cells tall.
    check container.gridRects.len == 4
    check container.gridRects[0].col == 0
    check container.gridRects[0].row == 0
    check container.gridRects[0].width == 10
    check container.gridRects[0].height == 2
    check container.gridRects[1].col == 10
    check container.gridRects[1].row == 0
    check container.gridRects[1].width == 10
    check container.gridRects[2].col == 0
    check container.gridRects[2].row == 2
    check container.gridRects[3].col == 10
    check container.gridRects[3].row == 2

    # Verify the rendered cells. Top-left cell starts at (0, 0) and
    # carries "AAAA" then 6 spaces; column 10 begins "BBBB". Row 1 has
    # "CCCC" / "DDDD".
    check h.cellAt(0, 0).rune == Rune('A'.ord)
    check h.cellAt(0, 1).rune == Rune('A'.ord)
    check h.cellAt(0, 2).rune == Rune('A'.ord)
    check h.cellAt(0, 3).rune == Rune('A'.ord)
    check h.cellAt(0, 10).rune == Rune('B'.ord)
    check h.cellAt(0, 13).rune == Rune('B'.ord)
    # Row 2 starts the second grid row (each row track = 2 cells).
    check h.cellAt(2, 0).rune == Rune('C'.ord)
    check h.cellAt(2, 3).rune == Rune('C'.ord)
    check h.cellAt(2, 10).rune == Rune('D'.ord)
    check h.cellAt(2, 13).rune == Rune('D'.ord)

    h.dispose()

  test "test_grid_three_columns_with_gutter":
    let h = newTerminalTestHarness(40, 4)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 2,
        layout = clGrid)
      container.setGridProps(GridProps(
        size: GridSize(cols: 3, rows: 1),
        columns: @[GridTrack(kind: gtkFr, value: 1.0),
                   GridTrack(kind: gtkFr, value: 1.0),
                   GridTrack(kind: gtkFr, value: 1.0)],
        rows: @[GridTrack(kind: gtkFr, value: 1.0)],
        gutter: GridGutter(horizontal: 1, vertical: 0)))
      for label in ["X", "Y", "Z"]:
        let s = newStatic(r, label, width = cellWidth(label), height = 1)
        container.append(s.node)
      r.appendChild(root, container.node)
      root)

    # 20 cells - 2 gutters = 18 across 3 fr → 6/6/6.
    check container.gridRects[0].col == 0
    check container.gridRects[0].width == 6
    check container.gridRects[1].col == 7
    check container.gridRects[1].width == 6
    check container.gridRects[2].col == 14
    check container.gridRects[2].width == 6

    # Cell 0 starts X.
    check h.cellAt(0, 0).rune == Rune('X'.ord)
    # The gutter cell at col 6 is a space.
    check h.cellAt(0, 6).rune == Rune(' '.ord)
    check h.cellAt(0, 7).rune == Rune('Y'.ord)
    check h.cellAt(0, 13).rune == Rune(' '.ord)
    check h.cellAt(0, 14).rune == Rune('Z'.ord)

    h.dispose()
