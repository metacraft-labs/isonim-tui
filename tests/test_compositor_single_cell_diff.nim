## test_compositor_single_cell_diff
##
## Mutating a signal that affects exactly one screen cell must produce
## a driver emission targeted at that cell — cursor move + at most one
## SGR transition + one rune. Crucially, the emission must NOT contain
## a full-row repaint (which the M2 compositor would have produced).
##
## We mount a tree with a single text node, paint, capture the byte
## log, then mutate one character inside the text. The next paint
## should emit `\x1b[<row>;<col>H` followed by exactly one rune (and
## no SGR, since the style didn't change).

import unittest
import std/strutils
import isonim_tui

suite "M8: compositor single-cell diff":
  test "test_compositor_single_cell_diff":
    let h = newTerminalTestHarness(40, 3)
    var label: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      label = r.createTextNode("ABCDE")
      r.appendChild(root, label)
      root)

    # Clear the recorded bytes so we measure only the post-mutation
    # paint.
    h.clearBytesEmitted()

    # Mutate one character: 'C' → 'X' at column 2, row 0.
    h.renderer.setTextContent(label, "ABXDE")
    h.flush()

    let bytes = h.bytesEmitted()
    # The driver must have received *some* output (the paint did
    # commit a change).
    check bytes.len > 0

    # Cursor was moved to row 0, column 2 (1-based on the wire).
    check bytes.contains("\x1b[1;3H")

    # The payload byte after the cursor-move sequence is the new rune
    # 'X'. Find the cursor sequence and inspect what follows.
    let idx = bytes.find("\x1b[1;3H")
    check idx >= 0
    let afterCursor = bytes[idx + len("\x1b[1;3H") .. ^1]
    # First non-ESC byte after the cursor-move must be 'X'.
    check afterCursor.len > 0
    check afterCursor[0] == 'X'

    # The total byte count must be small (a couple-dozen bytes for the
    # cursor sequence + one rune is well under a full-row repaint).
    # A full-row repaint would emit at least 40 cells of payload plus
    # extras — call it > 60 bytes. Single-cell diff stays under 20.
    check bytes.len < 30

    # The dirty region snapshot reflects the targeted change.
    let dirty = h.dirtyRegions()
    check dirty.len == 1
    check dirty[0].row == 0
    check dirty[0].col == 2
    check dirty[0].width == 1

    h.dispose()
