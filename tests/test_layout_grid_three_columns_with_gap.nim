## test_layout_grid_three_columns_with_gap
##
## A 3-column grid with `gap: 1` in 92 cells produces three 30-cell
## columns separated by 1-cell gaps: 30 + 1 + 30 + 1 + 30 = 92.
## Verifies the grid-layout track resolver and the gap accounting.

import unittest

import isonim_tui

suite "M3: grid three columns with gap":
  test "test_layout_grid_three_columns_with_gap":
    # 3 columns each 1fr, gap = 1 cell between columns.
    let cols = parseTemplate("1fr 1fr 1fr", gap = 1)
    let rows = parseTemplate("1fr", gap = 0)

    var grid = newGrid(cols, rows)
    grid.place(handle = 101, col = 0, row = 0)
    grid.place(handle = 102, col = 1, row = 0)
    grid.place(handle = 103, col = 2, row = 0)

    # Resolve in 92x10 cells.
    let rects = grid.resolveLayout(92, 10)

    # 92 - 2 gaps = 90 cells across 3 fr tracks → 30/30/30.
    check rects[0].width == 30
    check rects[1].width == 30
    check rects[2].width == 30

    # Heights are full row.
    check rects[0].height == 10
    check rects[1].height == 10
    check rects[2].height == 10

    # Columns are positioned with 1-cell gaps between them.
    check rects[0].col == 0
    check rects[1].col == 31  # 30 + 1
    check rects[2].col == 62  # 30 + 1 + 30 + 1

    # Total accounted for: last column's right edge = 92.
    check rects[2].col + rects[2].width == 92

    # Inter-column gap is exactly 1 cell.
    check rects[1].col - (rects[0].col + rects[0].width) == 1
    check rects[2].col - (rects[1].col + rects[1].width) == 1
