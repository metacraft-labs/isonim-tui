## test_layout_cell_snap_distributes_error
##
## Three siblings with `flex: 1` (i.e. `1fr 1fr 1fr`) inside a 91-cell
## parent produce 30/30/31 cells. The total is exactly 91; no siblings
## overlap and there's no leftover slack. Validates the cell-snap
## error-distribution contract.

import unittest

import isonim_tui
import isonim/layout/yoga_bindings

suite "M3: cell-snap distributes error":
  test "test_layout_cell_snap_distributes_error":
    let layout = newTerminalLayout(91, 1)
    discard layout.engine.registerNode(1)
    discard layout.engine.registerNode(2)
    discard layout.engine.registerNode(3)
    discard layout.engine.registerNode(4)
    layout.engine.addChild(1, 2)
    layout.engine.addChild(1, 3)
    layout.engine.addChild(1, 4)

    let root = layout.engine.nodes[0].yogaNode
    YGNodeStyleSetWidth(root, 91.0.cfloat)
    YGNodeStyleSetHeight(root, 1.0.cfloat)
    YGNodeStyleSetFlexDirection(root, YGFlexDirection.Row)

    for i in 1 .. 3:
      let n = layout.engine.nodes[i].yogaNode
      YGNodeStyleSetFlexGrow(n, 1.0.cfloat)
      YGNodeStyleSetHeight(n, 1.0.cfloat)

    layout.calculateLayoutInCells()

    let r2 = layout.cellRect(2)
    let r3 = layout.cellRect(3)
    let r4 = layout.cellRect(4)

    # Yoga raw widths are 30.333... each; snapped sizes must be
    # integer and sum to 91.
    check r2.width + r3.width + r4.width == 91

    # No two are larger than 31 or smaller than 30.
    for w in [r2.width, r3.width, r4.width]:
      check w >= 30
      check w <= 31

    # Exactly one of the three is 31 (the leftover absorber).
    var thirties = 0
    var thirtyOnes = 0
    for w in [r2.width, r3.width, r4.width]:
      if w == 30: inc thirties
      elif w == 31: inc thirtyOnes
    check thirties == 2
    check thirtyOnes == 1

    # No overlap: the right edge of each child lines up with the
    # left edge of the next (no leftover slack).
    check r2.col == 0
    check r3.col == r2.col + r2.width
    check r4.col == r3.col + r3.width
    check r4.col + r4.width == 91

    layout.dispose()
