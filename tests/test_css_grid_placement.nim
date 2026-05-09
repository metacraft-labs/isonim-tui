## test_css_grid_placement
##
## Auto-flow placement: given an N-column grid and a list of children,
## verify each child lands at the expected (row, col). Pure-function
## test of `placeChildren`.

import unittest
import isonim_tui

suite "M5 grid: auto-flow placement":

  test "test_three_columns_five_children":
    # 3-column grid; 5 children, all 1x1.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    check placements.len == 5
    check (placements[0].row, placements[0].col) == (0, 0)
    check (placements[1].row, placements[1].col) == (0, 1)
    check (placements[2].row, placements[2].col) == (0, 2)
    check (placements[3].row, placements[3].col) == (1, 0)
    check (placements[4].row, placements[4].col) == (1, 1)

  test "test_overflow_into_implicit_rows":
    # 2-column grid, 5 children → rows 0..2 with the last row half-full.
    let p = GridProps(
      size: GridSize(cols: 2, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    var inputs: seq[GridChildProps]
    for _ in 0 ..< 5:
      inputs.add(GridChildProps(colSpan: 1, rowSpan: 1))
    let placements = placeChildren(p, inputs)
    check placements[0] == GridPlacement(col: 0, row: 0, colSpan: 1, rowSpan: 1)
    check placements[1] == GridPlacement(col: 1, row: 0, colSpan: 1, rowSpan: 1)
    check placements[2] == GridPlacement(col: 0, row: 1, colSpan: 1, rowSpan: 1)
    check placements[3] == GridPlacement(col: 1, row: 1, colSpan: 1, rowSpan: 1)
    check placements[4] == GridPlacement(col: 0, row: 2, colSpan: 1, rowSpan: 1)

  test "test_single_column_stacks_vertically":
    let p = GridProps(
      size: GridSize(cols: 1, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    var inputs: seq[GridChildProps]
    for _ in 0 ..< 4:
      inputs.add(GridChildProps(colSpan: 1, rowSpan: 1))
    let placements = placeChildren(p, inputs)
    check placements[0].row == 0
    check placements[1].row == 1
    check placements[2].row == 2
    check placements[3].row == 3
    for pl in placements:
      check pl.col == 0
