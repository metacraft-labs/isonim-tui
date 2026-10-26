## test_compositor_grapheme_continuation
##
## A rune that takes no cell of its own — a combining mark, a zero-width
## joiner, a variation selector — goes WITH THE CELL BEFORE IT (`Cell.extra`)
## and is written right after that cell's rune, so the glyph a text holds is
## the glyph a terminal is sent:
##
##   * a decomposed `é` (`e` + U+0301) is one cell, and its bytes are both
##     runes;
##   * a ZWJ sequence keeps its joiner on the first emoji's cell, and the
##     layout is unchanged (no cell gained or lost);
##   * a VS16 stays with its base;
##   * a control character is never attached (a TAB would move the cursor).
##
## And the width fences (`text/fences`, CodeTracer-TUI-Terminal-Adaptation
## §6.5): with a question unanswered, a cell that may be drawn at another
## width is followed by `CSI <col> G` to the column the layout expects next —
## an EAW `A` character when the ambiguous policy is unknown, a Unicode 13
## code point when the terminal's tables are not known to cover it, a
## text-default pictograph when its width is unknown, a ZWJ / VS16 sequence
## when the terminal is not known to cluster. Box drawing never takes one,
## ASCII never does, and the zero value fences nothing.
##
## Real compositor, real headless driver, the production byte paths
## (`emitRegion`, `encodeAnsi`); no mocks.

import std/[strutils, unicode]
import unittest

import isonim_tui
import isonim_tui/testing/snapshot/ansi as snapAnsi

proc composite(text: string; fences = WidthFences()): (ScreenBuffer, string) =
  let renderer = TerminalRenderer()
  let root = renderer.createElement("div")
  let row = renderer.createElement("div")
  renderer.appendChild(row, renderer.createTextNode(text))
  renderer.appendChild(root, row)
  let driver = newHeadlessDriver(24, 2)
  let comp = newCompositor(24, 2, awNarrow)
  comp.fences = fences
  comp.paint(root, driver)
  (driver.buffer, snapAnsi.encodeAnsi(driver.buffer, fences))

suite "isonim-tui: a grapheme's zero-width runes go with its cell":

  test "a decomposed é is one cell holding both runes":
    let (buf, bytes) = composite("aéb")
    check $buf[0, 0].rune == "a"
    check $buf[0, 1].rune == "e"
    check buf[0, 1].extra == "́"
    check $buf[0, 2].rune == "b"
    check cellText(buf[0, 1]) == "é"
    check "aéb" in bytes

  test "a ZWJ sequence keeps its joiner; no cell gained or lost":
    let (buf, bytes) = composite("x\u{1F469}‍\u{1F4BB}y")
    check $buf[0, 0].rune == "x"
    check buf[0, 1].rune.int32 == 0x1F469
    check buf[0, 1].width == 2
    check buf[0, 1].extra == "‍"
    check buf[0, 2].width == 0
    check buf[0, 3].rune.int32 == 0x1F4BB
    check $buf[0, 5].rune == "y"
    check "\u{1F469}‍\u{1F4BB}y" in bytes

  test "a VS16 stays with its base; a TAB is never attached":
    let (buf, _) = composite("❤️z")
    check buf[0, 0].rune.int32 == 0x2764
    check buf[0, 0].extra == "️"
    let (tabbed, bytes) = composite("a\tb")
    check tabbed[0, 0].extra == ""
    check '\t' notin bytes

  test "a changed mark is a changed cell (equality and the row hash)":
    let (a, _) = composite("é")
    let (b, _) = composite("è")
    check a[0, 0] != b[0, 0]
    check a.rows[0].contentHash != b.rows[0].contentHash

suite "isonim-tui: width fences (Terminal-Adaptation §6.5)":

  test "the zero value fences nothing; ASCII and box drawing never":
    let (_, plain) = composite("ab…─\u{1FB87}")
    check "G" notin plain.replace("\x1b[0m", "")
    var all = WidthFences(ambiguousUnknown: true, unicode13Unknown: true,
                          pictographsUnknown: true, noClusters: true)
    let (_, ascii) = composite("plain ascii ─│┌", all)
    for i in 0 ..< ascii.len - 1:
      if ascii[i] == '\x1b' and ascii[i + 1] == '[':
        check not ascii[i + 2 .. ^1].split({'m', 'H'})[0].endsWith("G")

  test "an EAW A character, ambiguous unknown: the next cell placed":
    let (_, bytes) = composite("a…b", WidthFences(ambiguousUnknown: true))
    check "…\x1b[3Gb" in bytes
    let (_, known) = composite("a…b")
    check "…b" in known

  test "a Unicode 13 code point, the terminal's tables unknown":
    let (_, bytes) = composite("a\u{1FB87}b",
                               WidthFences(unicode13Unknown: true))
    check "\u{1FB87}\x1b[3Gb" in bytes

  test "a text-default pictograph, its width unknown":
    let (_, bytes) = composite("a⏮b", WidthFences(pictographsUnknown: true))
    check "⏮\x1b[3Gb" in bytes

  test "a ZWJ sequence on a terminal not known to cluster":
    let (_, bytes) = composite("\u{1F469}‍\u{1F4BB}y",
                               WidthFences(noClusters: true))
    # Each part is placed: the joined head, then the second emoji.
    check "\u{1F469}‍\x1b[3G\u{1F4BB}" in bytes
    let (_, clustered) = composite("\u{1F469}‍\u{1F4BB}y")
    check "\u{1F469}‍\u{1F4BB}y" in clustered

  test "emitRegion fences inside a region, never past its end":
    let (buf, _) = composite("a…b…", WidthFences(ambiguousUnknown: true))
    var cells: seq[Cell] = @[]
    for c in 0 ..< 4: cells.add buf[0, c]
    let (bytes, _) = emitRegion(defaultStyle(),
      CellRegion(row: 0, col: 0, width: 4, cells: cells),
      WidthFences(ambiguousUnknown: true))
    check "…\x1b[3Gb" in bytes
    check not bytes.endsWith("G")
