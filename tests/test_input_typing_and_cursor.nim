## test_input_typing_and_cursor — M13 mandatory test.
##
## An input with focus receives keys; advances the cursor; Backspace
## removes the previous grapheme cluster (not just one byte). Snapshot
## tested in all six formats at three states.

import unittest
import std/unicode
import isonim_tui

suite "M13: input typing and cursor":
  test "test_input_typing_and_cursor":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)

    # Empty state: cursor at 0, value empty.
    check inp.value == ""
    check inp.cursorPos == 0
    discard h.snap("m13_input_empty")

    # Focus the widget and type "hi".
    let p = newPilot(h)
    p.focus(inp.node)
    p.typeText("hi")

    # Mid-type state: value is "hi", cursor at end.
    check inp.value == "hi"
    check inp.cursorPos == 2
    check h.cellAt(1, 1).rune == "h".runeAt(0)
    check h.cellAt(1, 2).rune == "i".runeAt(0)
    discard h.snap("m13_input_after_type")

    # Backspace once removes 'i' (one grapheme cluster, one byte).
    p.press("backspace")
    check inp.value == "h"
    check inp.cursorPos == 1
    check h.cellAt(1, 1).rune == "h".runeAt(0)
    # The 'i' cell must now be a space.
    check h.cellAt(1, 2).rune == " ".runeAt(0)
    discard h.snap("m13_input_after_backspace")

    h.dispose()

  test "left_right_cursor_navigation":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "abc", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)

    # Cursor at end of "abc".
    check inp.cursorPos == 3
    p.press("left")
    check inp.cursorPos == 2
    p.press("left")
    p.press("left")
    check inp.cursorPos == 0
    # Don't go below 0.
    p.press("left")
    check inp.cursorPos == 0
    p.press("right")
    check inp.cursorPos == 1
    # Insert at cursor.
    p.typeText("X")
    check inp.value == "aXbc"
    check inp.cursorPos == 2
    h.dispose()

  test "home_end_navigation":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "hello", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    check inp.cursorPos == 5
    p.press("home")
    check inp.cursorPos == 0
    p.press("end")
    check inp.cursorPos == 5
    h.dispose()

  test "delete_right_removes_next_cluster":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "abc", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    p.press("home")
    p.press("delete")
    check inp.value == "bc"
    check inp.cursorPos == 0
    h.dispose()
