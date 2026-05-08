## test_dock_pinned_left
##
## A node with `dock = left` is removed from the parent's main-axis
## flow; siblings reflow into the remaining region. Verifies the dock
## algorithm in `layout/dock.nim`.

import unittest

import isonim_tui

suite "M3: dock pinned left":
  test "test_dock_pinned_left":
    # Parent: 80 cells wide x 10 cells high.
    let parent = CellRect(col: 0, row: 0, width: 80, height: 10)
    let docks = @[
      DockSpec(handle: 1, edge: deLeft, size: 20)
    ]
    let res = applyDocks(parent, docks)

    # The docked rect is at the parent's left edge.
    check res.rects.len == 1
    let rect = res.rects[0]
    check rect.col == 0
    check rect.row == 0
    check rect.width == 20
    check rect.height == 10

    # The inner content area starts after the dock (at col=20) and is
    # 80 - 20 = 60 cells wide. Siblings get this region.
    check res.inner.col == 20
    check res.inner.row == 0
    check res.inner.width == 60
    check res.inner.height == 10

  test "dock right + bottom carve off correctly":
    let parent = CellRect(col: 0, row: 0, width: 100, height: 30)
    let docks = @[
      DockSpec(handle: 1, edge: deRight, size: 10),
      DockSpec(handle: 2, edge: deBottom, size: 5),
    ]
    let res = applyDocks(parent, docks)
    check res.rects[0].col == 90  # 100 - 10
    check res.rects[0].width == 10
    check res.rects[0].height == 30   # full height before bottom dock
    check res.rects[1].row == 25  # 30 - 5
    check res.rects[1].height == 5
    check res.rects[1].width == 90  # 100 - 10 (after right dock)
    check res.inner == CellRect(col: 0, row: 0, width: 90, height: 25)
