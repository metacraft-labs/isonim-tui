## test_css_grid_track_resolver
##
## Pure-function test of the CSS-driven grid track resolver. Each
## sub-test feeds typed `GridProps` (the same shape the cascade
## produces) plus a child placement list into `resolveCssGrid` and
## verifies the resulting cell rectangles.
##
## No mocks, no widgets — just the resolver math.

import unittest
import isonim_tui

template fr(v: float64): GridTrack = GridTrack(kind: gtkFr, value: v)
template fixed(v: float64): GridTrack = GridTrack(kind: gtkFixed, value: v)
template gauto(): GridTrack = GridTrack(kind: gtkAuto, value: 1.0)
template pct(v: float64): GridTrack = GridTrack(kind: gtkPercent, value: v)

suite "M5 grid: track resolver corpus":

  test "test_three_fr_columns_distribute_evenly":
    # 3 columns each 1fr, gap=0, parent=90 cells → 30/30/30.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[fr(1.0), fr(1.0), fr(1.0)],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 90, 10)
    check rects.len == 3
    check rects[0].col == 0
    check rects[0].width == 30
    check rects[1].col == 30
    check rects[1].width == 30
    check rects[2].col == 60
    check rects[2].width == 30
    check rects[0].height == 10
    check rects[1].height == 10
    check rects[2].height == 10

  test "test_mixed_fixed_and_fr":
    # 1st = 10 cells fixed; 2nd = 1fr; 3rd = 2fr. Parent = 100, gap = 0.
    # Remaining = 90 → fr1 = 30, fr2 = 60.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[fixed(10.0), fr(1.0), fr(2.0)],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 100, 10)
    check rects[0].width == 10
    check rects[1].width == 30
    check rects[2].width == 60
    check rects[0].col == 0
    check rects[1].col == 10
    check rects[2].col == 40

  test "test_percentage_track":
    # 25% + 1fr + 25%. Parent = 80, gap = 0.
    # 25% of 80 = 20 each → remaining = 40 → 1fr column = 40.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[pct(25.0), fr(1.0), pct(25.0)],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 80, 5)
    check rects[0].width == 20
    check rects[1].width == 40
    check rects[2].width == 20

  test "test_auto_track_falls_back_to_one_cell":
    # M5 grid scope: `auto` resolves to 1 cell minimum (full intrinsic
    # measurement is deferred — see M5 deferred list).
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[gauto(), fr(1.0), gauto()],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 50, 5)
    check rects[0].width == 1
    check rects[2].width == 1
    # 1fr eats the remainder = 50 - 1 - 1 = 48.
    check rects[1].width == 48

  test "test_gutter_consumes_cells":
    # 3 columns each 1fr in 92 cells with gutter 1 → 30 + 1 + 30 + 1 + 30.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[fr(1.0), fr(1.0), fr(1.0)],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 1, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 92, 10)
    check rects[0].col == 0
    check rects[0].width == 30
    check rects[1].col == 31
    check rects[2].col == 62
    check rects[2].col + rects[2].width == 92

  test "test_grid_size_only_synthesises_fr_columns":
    # No grid-columns provided — `grid-size: 4` infers 4 × 1fr columns.
    let p = GridProps(
      size: GridSize(cols: 4, rows: 1),
      columns: @[],     # empty: synthesised from cols
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let rects = resolveCssGrid(p, placements, 80, 5)
    check rects[0].width == 20
    check rects[1].width == 20
    check rects[2].width == 20
    check rects[3].width == 20
