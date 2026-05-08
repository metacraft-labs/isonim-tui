## test_segment_dedup
##
## A region of N cells that share a single style must emit one SGR
## transition followed by N runes — not N × (SGR + rune). This is the
## SGR-deduplication pass (port of Textual's
## `_segment_tools.simplify_segments`).
##
## The compositor's `emitRegion` is the unit under test. We construct
## a region of 80 styled cells and assert the byte sequence contains
## exactly one ANSI ESC sequence (the cursor-move counts as another;
## the SGR comes once before the cells; thereafter the run is pure
## payload bytes).

import unittest
import std/[strutils, unicode]
import isonim_tui
import isonim_tui/text/ansi as ansiMod

suite "M8: segment dedup":
  test "test_segment_dedup":
    # Build a region of 80 cells, all with `attrBold` and `acRed`
    # foreground.
    var cells = newSeq[Cell]()
    for _ in 0 ..< 80:
      cells.add Cell(rune: Rune('A'.ord),
                     fg: ansiColor(acRed),
                     bg: defaultColor(),
                     attrs: {attrBold},
                     width: 1)
    let region = CellRegion(row: 0, col: 0, width: 80, cells: cells)
    let prev = defaultStyle()
    let (bytes, _) = emitRegion(prev, region)

    # Count ESC bytes. Two are expected: one for `cursorTo(0,0)` and
    # one for the SGR transition `\x1b[1;31m` (bold + red fg).
    var escCount = 0
    for c in bytes:
      if c == '\x1b': inc escCount
    check escCount == 2

    # Confirm the SGR run has exactly the bold and red parameters.
    check bytes.contains("\x1b[1;31m")

    # Confirm exactly 80 'A' bytes followed the SGR.
    var aCount = 0
    for c in bytes:
      if c == 'A': inc aCount
    check aCount == 80

    # Total bytes: cursorTo("\x1b[1;1H") = 6 bytes,
    # SGR ("\x1b[1;31m") = 7 bytes, plus 80 runes = 93.
    check bytes.len == 6 + 7 + 80

  test "test_segment_dedup_two_styles":
    # Mixed run: 40 red cells then 40 blue cells. We expect exactly
    # two SGR transitions (one initial, one mid-run).
    var cells = newSeq[Cell]()
    for _ in 0 ..< 40:
      cells.add Cell(rune: Rune('A'.ord),
                     fg: ansiColor(acRed),
                     bg: defaultColor(),
                     attrs: {},
                     width: 1)
    for _ in 0 ..< 40:
      cells.add Cell(rune: Rune('B'.ord),
                     fg: ansiColor(acBlue),
                     bg: defaultColor(),
                     attrs: {},
                     width: 1)
    let region = CellRegion(row: 0, col: 0, width: 80, cells: cells)
    let (bytes, _) = emitRegion(defaultStyle(), region)
    # ESC count: 1 cursorTo + 2 SGR transitions = 3.
    var escCount = 0
    for c in bytes:
      if c == '\x1b': inc escCount
    check escCount == 3

  test "test_segment_dedup_against_strip_textual_baseline":
    # Sanity: Textual's reference for "row of identical-style cells"
    # is a single `Segment(text * width, style)`. Our `emitRegion`
    # should produce the same total payload size: the SGR
    # parameter sequence plus the cumulative rune width. We assert
    # that the per-cell SGR cost vanishes.
    var cells = newSeq[Cell]()
    let style = newStyle(ansiColor(acGreen), defaultColor(), {})
    let perCellSgrLen = renderSgr(defaultStyle(), style).len
    for _ in 0 ..< 50:
      cells.add Cell(rune: Rune('Z'.ord),
                     fg: style.fg, bg: style.bg, attrs: style.attrs,
                     width: 1)
    let region = CellRegion(row: 0, col: 0, width: 50, cells: cells)
    let (bytes, _) = emitRegion(defaultStyle(), region)
    # With dedup: one SGR + 50 runes + cursor.
    let cursorLen = ansiMod.cursorTo(0, 0).len
    check bytes.len == cursorLen + perCellSgrLen + 50
