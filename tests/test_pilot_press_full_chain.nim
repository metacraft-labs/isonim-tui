## test_pilot_press_full_chain
##
## A counter app driven by `h.pilot.press("enter")` through the real
## input pipeline (synthetic event → driver → renderer → compositor)
## increments its visible count by 1; `h.cellAt(...).rune` reflects the
## new digit. The recorded byte stream contains the expected ANSI for a
## single-cell update (cursor positioning + a digit byte).

import unittest
import isonim_tui
import std/[unicode, strutils]

suite "M2: pilot.press full chain":
  test "test_pilot_press_full_chain":
    let h = newTerminalTestHarness(20, 3)
    var counter = 0
    var label: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      label = r.createTextNode("0")
      r.appendChild(root, label)
      r.addEventListener(root, "keydown", proc() =
        inc counter
        r.setTextContent(label, $counter))
      root)

    check h.cellAt(0, 0).rune == Rune('0'.ord)

    let p = newPilot(h)
    # Clear pre-mount bytes so we can assert on the *next* batch.
    h.clearBytesEmitted()
    p.press("enter")

    # Visible state advanced.
    check counter == 1
    check h.cellAt(0, 0).rune == Rune('1'.ord)

    # Recorded byte stream contains the new digit and a cursor-move.
    let bytes = h.bytesEmitted()
    check bytes.len > 0
    check '1' in bytes
    # ANSI cursor-positioning starts with ESC [
    check "\x1b[" in bytes

    h.dispose()
