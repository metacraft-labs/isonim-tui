## test_compositor_ambiguous_width_policy
##
## A compositor lays East Asian Width `A` characters out under an EXPLICIT
## policy (`newCompositor(…, ambiguous)`), never under the thread-local
## `setAmbiguousWidth`. A front-end that measured its terminal drawing them
## two cells wide hands `awWide`, and the composited buffer then places the
## cell after `…` two columns on — exactly where that terminal draws it — so
## the front-end's own layout and the compositor's agree.
##
## Real compositor, real headless driver; no mocks.

import std/unicode
import unittest

import isonim_tui

proc build(r: TerminalRenderer): TerminalNode =
  result = r.createElement("div")
  let row = r.createElement("div")
  r.appendChild(row, r.createTextNode("…x─y"))
  r.appendChild(result, row)

proc composite(ambiguous: AmbiguousWidth): ScreenBuffer =
  let renderer = TerminalRenderer()
  let driver = newHeadlessDriver(20, 2)
  let comp = newCompositor(20, 2, ambiguous)
  check comp.ambiguous == ambiguous
  comp.paint(build(renderer), driver)
  driver.buffer

suite "compositor: the ambiguous-width policy is an input":

  test "narrow: each EAW A character is one cell":
    let buf = composite(awNarrow)
    check $buf[0, 0].rune == "…"
    check buf[0, 0].width == 1
    check $buf[0, 1].rune == "x"
    check $buf[0, 2].rune == "─"
    check $buf[0, 3].rune == "y"

  test "wide: each EAW A character takes two cells, a ghost beside it":
    let buf = composite(awWide)
    check $buf[0, 0].rune == "…"
    check buf[0, 0].width == 2
    check buf[0, 1].width == 0
    check $buf[0, 2].rune == "x"
    check $buf[0, 3].rune == "─"
    check buf[0, 3].width == 2
    check $buf[0, 5].rune == "y"

  test "the thread-local policy does not reach a compositor given one":
    setAmbiguousWidth(awWide)
    let buf = composite(awNarrow)
    setAmbiguousWidth(awNarrow)
    check $buf[0, 1].rune == "x"
