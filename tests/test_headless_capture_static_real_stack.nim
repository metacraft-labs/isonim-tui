## test_headless_capture_static_real_stack
##
## A static `text "hi"` rendered through `TerminalTestHarness` produces
## a `ScreenBuffer` whose row 0 starts with "hi". The full chain is
## exercised: real renderer, real compositor, real headless driver.

import unittest
import isonim_tui
import std/unicode

suite "M2: HeadlessDriver capture (real stack)":
  test "test_headless_capture_static_real_stack":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let txt = r.createTextNode("hi")
      r.appendChild(root, txt)
      root)

    # Buffer-side check: the cells reflect the rendered string.
    check h.cellAt(0, 0).rune == Rune('h'.ord)
    check h.cellAt(0, 1).rune == Rune('i'.ord)
    # The driver recorded SGR/cursor bytes — the real chain ran.
    check h.bytesEmitted().len > 0
    # Buffer is the right size.
    let buf = h.screenBuffer()
    check buf.cols == 20
    check buf.rowsCount == 5

    h.dispose()
