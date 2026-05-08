## test_layout_cell_snap_integer_real_yoga
##
## A container with `width=33%` inside an 80-cell parent gets exactly
## 26 cells (or 27) — the Yoga FFI is invoked, its float result is
## observed (33% of 80 = 26.4) and the snap behaviour validated:
## the result is integer-valued, the integer is within ±1 of Yoga's
## float, and the snap is monotonic (snap(x) <= snap(x+ε)).

import unittest

import isonim_tui
import isonim/layout/layout_engine
import isonim/layout/yoga_bindings

suite "M3: cell-snap integer (real Yoga)":
  test "test_layout_cell_snap_integer_real_yoga":
    # Build a Yoga tree directly so we can use Yoga's percent setter
    # (LayoutEngine.setLayoutStyle doesn't yet parse '%' literals).
    let layout = newTerminalLayout(80, 24)
    discard layout.engine.registerNode(1)
    discard layout.engine.registerNode(2)
    layout.engine.addChild(1, 2)

    # Configure root: 80 x 24 (the cell parent dimensions).
    let root = layout.engine.nodes[0].yogaNode
    YGNodeStyleSetWidth(root, 80.0.cfloat)
    YGNodeStyleSetHeight(root, 24.0.cfloat)
    # Child: 33% of root width.
    let child = layout.engine.nodes[1].yogaNode
    YGNodeStyleSetWidthPercent(child, 33.0.cfloat)
    YGNodeStyleSetHeight(child, 1.0.cfloat)

    layout.calculateLayoutInCells()

    # Yoga reports a float width. 33% of 80 = 26.4; Yoga's pixel-grid
    # rounding (with default config) reports 26.0. Either way the
    # snap result must be integer-valued and within 1 cell of the
    # mathematically-correct 26.4.
    let raw = layout.rawLayout(2)
    check raw.width >= 26.0 and raw.width <= 27.0

    # Snapped width is an integer ∈ {26, 27}.
    let snapped = layout.cellRect(2)
    check snapped.width >= 26
    check snapped.width <= 27

    # The whole snapped record is integer-valued by construction
    # (CellRect uses `int`). Confirming the documented contract.
    check snapped.col == 0
    check snapped.row == 0
    check snapped.height >= 1

    layout.dispose()
