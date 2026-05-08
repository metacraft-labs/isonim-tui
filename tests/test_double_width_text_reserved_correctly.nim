## test_double_width_text_reserved_correctly
##
## A label containing "東京" (Tokyo) is allocated 4 cells of width by
## the cell-snap layout — 2 East-Asian-Wide ideographs × 2 cells each
## — *not* 2 (codepoint count) and *not* 6 (UTF-8 byte count).
##
## Verifies that `text/width.displayWidth` is the source of truth for
## intrinsic node sizing.

import unittest

import isonim_tui
import isonim/layout/yoga_bindings

suite "M3: double-width text reserved correctly":
  test "test_double_width_text_reserved_correctly":
    # measureTextCells must report 4 for "東京" (each ideograph is
    # East-Asian-Wide → 2 cells).
    check measureTextCells("東京") == 4
    check measureTextCells("Hi") == 2
    # Byte-count and codepoint-count are *not* what we use:
    check len("東京") == 6           # UTF-8 bytes
    check measureTextCells("東京") != 6
    check measureTextCells("東京") != 2

    # Reserve cells through the layout engine.
    let layout = newTerminalLayout(40, 5)
    discard layout.engine.registerNode(1)
    discard layout.engine.registerNode(2)
    layout.engine.addChild(1, 2)

    let root = layout.engine.nodes[0].yogaNode
    YGNodeStyleSetWidth(root, 40.0.cfloat)
    YGNodeStyleSetHeight(root, 5.0.cfloat)
    YGNodeStyleSetFlexDirection(root, YGFlexDirection.Row)

    # Reserve cells for the label using `text/width.displayWidth`.
    layout.reserveTextCells(2, "東京")

    layout.calculateLayoutInCells()

    let labelRect = layout.cellRect(2)
    # The label's width is at least 4 cells (its `min-width` set by
    # reserveTextCells); could be larger if the parent stretches it,
    # but the *minimum* is what we assert.
    check labelRect.width >= 4

    layout.dispose()
