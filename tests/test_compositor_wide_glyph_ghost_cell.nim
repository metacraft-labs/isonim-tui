## test_compositor_wide_glyph_ghost_cell
##
## A width-2 glyph owns TWO columns, and the composited `ScreenBuffer` has to
## say so in the second one.
##
## `compositor.paintEntryOnto` used to `continue` past every width-0 cell in a
## strip, which meant the ghost `rawCellsForEntry` builds beside a wide glyph
## was never stamped -- the freshly-allocated buffer's `spaceCell()` (rune ' ',
## width 1) stayed in that column and the composited buffer contained no ghost
## at all. `testing/snapshot/ansi.encodeAnsi` skips width-0 cells and emits
## everything else, so it then wrote a REAL SPACE after every wide glyph.
##
## Measured on "┌世界─┐" at 20x3: the buffer placed `┐` at column 6 while a
## terminal fed the emitted bytes placed it at column 8 -- one column of drift
## per wide glyph, accumulating rightwards. Nothing in this repository could
## see it, because every one of the six snapshot formats is derived from the
## same buffer that was wrong.
##
## This test therefore asserts BOTH halves: the buffer's cell pair, and the
## bytes `encodeAnsi` emits from it.

import std/[strutils, unicode]
import unittest

import isonim_tui

const WideRow = "┌世界─┐"

proc buildWide(r: TerminalRenderer): TerminalNode =
  result = r.createElement("div")
  let row = r.createElement("div")
  r.appendChild(row, r.createTextNode(WideRow))
  r.appendChild(result, row)

proc buildNarrow(r: TerminalRenderer): TerminalNode =
  result = r.createElement("div")
  let row = r.createElement("div")
  r.appendChild(row, r.createTextNode("plain ascii"))
  r.appendChild(result, row)

suite "compositor: the trailing half of a wide glyph":

  test "the composited buffer carries a ghost beside every width-2 cell":
    let h = newTerminalTestHarness(20, 3)
    h.mount(buildWide)
    h.flush()
    let buf = h.driver.buffer

    # The pair, column by column. `┌` is width 1, `世` and `界` are width 2 and
    # each owns the column to its right, `─` and `┐` are width 1 again.
    check $buf[0, 0].rune == "┌"
    check buf[0, 0].width == 1
    check $buf[0, 1].rune == "世"
    check buf[0, 1].width == 2
    check buf[0, 2].rune.int32 == 0
    check buf[0, 2].width == 0
    check $buf[0, 3].rune == "界"
    check buf[0, 3].width == 2
    check buf[0, 4].rune.int32 == 0
    check buf[0, 4].width == 0
    check $buf[0, 5].rune == "─"
    check buf[0, 5].width == 1
    check $buf[0, 6].rune == "┐"
    check buf[0, 6].width == 1

    # Counted as well as spot-checked, so a buffer that had lost a pair
    # somewhere off to the right cannot pass on the six cells above.
    var wide, ghosts = 0
    for r in 0 ..< buf.rowsCount:
      for c in 0 ..< buf.cols:
        case buf[r, c].width
        of 0: inc ghosts
        of 2: inc wide
        else: discard
    check wide == 2
    check ghosts == wide

    h.dispose()

  test "encodeAnsi emits no space between a wide glyph and its neighbour":
    # THE SYMPTOM, asserted on the bytes rather than on the model that produced
    # them. A space here is invisible to every other Tier-1 assertion and moves
    # everything to its right by one column on a real terminal.
    let h = newTerminalTestHarness(20, 3)
    h.mount(buildWide)
    h.flush()
    let emitted = encodeAnsi(h.driver.buffer)
    let firstRow = emitted.split('\n')[0]
    check firstRow.startsWith(WideRow)
    check not firstRow.startsWith("┌世 ")
    # `encodePlaintext` skips width-0 cells by its own documented rule, so it
    # agrees only if the ghosts are really there.
    check encodePlaintext(h.driver.buffer).split('\n')[0] == WideRow
    h.dispose()

  test "a narrow row composites with no ghosts at all":
    # The negative twin: the assertions above are satisfied for free by a
    # `paintEntryOnto` that stamped a ghost everywhere.
    let h = newTerminalTestHarness(20, 3)
    h.mount(buildNarrow)
    h.flush()
    let buf = h.driver.buffer
    var ghosts = 0
    for r in 0 ..< buf.rowsCount:
      for c in 0 ..< buf.cols:
        if buf[r, c].width == 0: inc ghosts
    check ghosts == 0
    check encodePlaintext(buf).split('\n')[0] == "plain ascii"
    h.dispose()
