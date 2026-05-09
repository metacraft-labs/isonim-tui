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

  test "test_auto_track_sizes_to_widest_child":
    # M5 closure: `auto` tracks measure their children. The widest child
    # placed entirely in an auto track grows that track to its natural
    # width; the surrounding `fr` track absorbs the remainder.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[gauto(), fr(1.0), gauto()],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let naturals = @[
      NaturalSize(width: 7, height: 1),   # auto col 0 → 7 cells
      NaturalSize(width: 3, height: 1),   # fr col — natural ignored
      NaturalSize(width: 4, height: 1)]   # auto col 2 → 4 cells
    let rects = resolveCssGrid(p, placements, 50, 5, naturals)
    check rects[0].width == 7
    check rects[2].width == 4
    # 1fr eats the remainder = 50 - 7 - 4 = 39.
    check rects[1].width == 39
    check rects[0].col == 0
    check rects[1].col == 7
    check rects[2].col == 46

  test "test_auto_track_with_smaller_children":
    # Auto tracks size to the actual child width, not the container
    # width. With two `auto auto` columns and a 100-cell parent, two
    # short children stay short; we don't stretch them to fill.
    let p = GridProps(
      size: GridSize(cols: 2, rows: 1),
      columns: @[gauto(), gauto()],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let naturals = @[
      NaturalSize(width: 5, height: 1),
      NaturalSize(width: 8, height: 1)]
    let rects = resolveCssGrid(p, placements, 100, 5, naturals)
    check rects[0].width == 5
    check rects[1].width == 8
    check rects[0].col == 0
    check rects[1].col == 5

  test "test_auto_track_with_spanning_child":
    # A child spanning two `auto` tracks grows both: the per-track
    # first-pass size (max of single-track children) plus the
    # span-deficit distribution.
    let p = GridProps(
      size: GridSize(cols: 2, rows: 2),
      columns: @[gauto(), gauto()],
      rows: @[fr(1.0), fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    # Row 0: child 0 spans columns 0..1.
    # Row 1: child 1 in col 0 (width 3); child 2 in col 1 (width 4).
    let placements = @[
      GridPlacement(col: 0, row: 0, colSpan: 2, rowSpan: 1),
      GridPlacement(col: 0, row: 1, colSpan: 1, rowSpan: 1),
      GridPlacement(col: 1, row: 1, colSpan: 1, rowSpan: 1)]
    let naturals = @[
      NaturalSize(width: 11, height: 1),  # spanning child
      NaturalSize(width: 3,  height: 1),
      NaturalSize(width: 4,  height: 1)]
    let rects = resolveCssGrid(p, placements, 50, 4, naturals)
    # Column 0 starts at 3 (single-pass), column 1 at 4. Spanning child
    # demands 11; existing = 7, deficit = 4 → 2 to col 0, 2 to col 1.
    # Final: col 0 = 5, col 1 = 6, spanning child width = 11.
    check rects[0].width == 11
    check rects[0].col == 0
    check rects[1].col == 0
    check rects[1].width == 5
    check rects[2].col == 5
    check rects[2].width == 6

  test "test_auto_mixed_with_fr":
    # `auto fr fr` — fixed-width child in column 0, flexible content in
    # 1 and 2. Auto column shrinks to its natural width, fr columns
    # share the remainder.
    let p = GridProps(
      size: GridSize(cols: 3, rows: 1),
      columns: @[gauto(), fr(1.0), fr(1.0)],
      rows: @[fr(1.0)],
      gutter: GridGutter(horizontal: 0, vertical: 0))
    let placements = placeChildren(p, @[
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1),
      GridChildProps(colSpan: 1, rowSpan: 1)])
    let naturals = @[
      NaturalSize(width: 6, height: 1),   # auto col 0
      NaturalSize(width: 2, height: 1),   # fr col — natural ignored
      NaturalSize(width: 2, height: 1)]   # fr col — natural ignored
    let rects = resolveCssGrid(p, placements, 26, 4, naturals)
    check rects[0].width == 6
    # Remainder = 26 - 6 = 20 → split evenly across 2 fr tracks.
    check rects[1].width == 10
    check rects[2].width == 10
    check rects[0].col == 0
    check rects[1].col == 6
    check rects[2].col == 16

  test "test_auto_track_falls_back_to_one_cell_without_naturals":
    # Backward-compat: the no-`natural` overload still produces the
    # historical 1-cell fallback for `auto` tracks. Pre-M5-closure
    # callers (the resolver isn't always wired to a widget tree) keep
    # working.
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
