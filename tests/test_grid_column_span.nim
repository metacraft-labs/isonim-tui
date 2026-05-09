## test_grid_column_span
##
## A child with `column-span: 2` occupies two columns; subsequent
## children skip the spanned cells. Verifies the auto-flow placer
## respects per-child colSpan.

import unittest
import isonim_tui

suite "M5 grid: column-span":

  test "test_first_child_spans_two_columns":
    # 3-column grid. First child: 2x1 span. Then three 1x1 children.
    # Expected:
    #   row 0: [child0(0..1), child1(2)]
    #   row 1: [child2, child3, _]
    let p = GridProps(
      size: GridSize(cols: 3, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let inputs = @[
      GridChildProps(colSpan: 2, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)]
    let placements = placeChildren(p, inputs)
    check placements[0].row == 0
    check placements[0].col == 0
    check placements[0].colSpan == 2
    check placements[1].row == 0
    check placements[1].col == 2
    check placements[2].row == 1
    check placements[2].col == 0
    check placements[3].row == 1
    check placements[3].col == 1

  test "test_span_clamped_to_columns":
    # Column-span larger than the grid is clamped, not silently dropped.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let inputs = @[GridChildProps(colSpan: 99, rowSpan: 1)]
    let placements = placeChildren(p, inputs)
    check placements[0].colSpan == 3   # clamped to grid width
    check placements[0].col == 0
    check placements[0].row == 0

  test "test_row_span_consumes_lower_rows":
    # 2-column grid. First child spans 2 rows in column 0; then 3 small
    # children. Expected layout (X = first child):
    #   row 0: [X, c1]
    #   row 1: [X, c2]
    #   row 2: [c3, _]
    let p = GridProps(
      size: GridSize(cols: 2, rows: 0),
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let inputs = @[
      GridChildProps(colSpan: 1, rowSpan: 2),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)]
    let placements = placeChildren(p, inputs)
    check placements[0].row == 0
    check placements[0].col == 0
    check placements[0].rowSpan == 2
    check placements[1].row == 0
    check placements[1].col == 1
    check placements[2].row == 1
    check placements[2].col == 1
    check placements[3].row == 2
    check placements[3].col == 0

  test "test_resolved_rect_widths_for_spanned_cells":
    # 4 columns × 1fr each in 80 cells. A 2-column-span child occupies
    # 40 cells (2 × 20 = 40, plus zero gutter).
    let p = GridProps(
      size: GridSize(cols: 4, rows: 1),
      columns: @[
        GridTrack(kind: gtkFr, value: 1.0),
        GridTrack(kind: gtkFr, value: 1.0),
        GridTrack(kind: gtkFr, value: 1.0),
        GridTrack(kind: gtkFr, value: 1.0)],
      rows: @[GridTrack(kind: gtkFr, value: 1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let inputs = @[GridChildProps(colSpan: 2, rowSpan: 1),
                   GridChildProps(colSpan: 1, rowSpan: 1),
                   GridChildProps(colSpan: 1, rowSpan: 1)]
    let placements = placeChildren(p, inputs)
    let rects = resolveCssGrid(p, placements, 80, 5)
    check rects[0].col == 0
    check rects[0].width == 40
    check rects[1].col == 40
    check rects[1].width == 20
    check rects[2].col == 60
    check rects[2].width == 20
