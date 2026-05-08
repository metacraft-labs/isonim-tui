## test_input_password_mask — M13 mandatory test.
##
## With `password = true`, typing "hello" displays five "•" cells while
## the bound signal (here a closure-captured string) holds "hello".

import unittest
import std/unicode
import isonim_tui

suite "M13: input password mask":
  test "test_input_password_mask":
    let h = newTerminalTestHarness(20, 3)
    var bound = ""
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "", width = 12, border = bsRound,
                     password = true,
                     onChange = proc(v: string) = bound = v)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    p.typeText("hello")

    # The bound signal got the real value.
    check inp.value == "hello"
    check bound == "hello"

    # The visible cells are "•" U+2022, not 'h','e','l','l','o'.
    let bullet = "\xe2\x80\xa2".runeAt(0)
    for col in 1 .. 5:
      check h.cellAt(1, col).rune == bullet
    # The 6th column should be a space (cursor parking spot, not masked).
    check h.cellAt(1, 6).rune == " ".runeAt(0)

    # Backspace removes one mask cell + the underlying char.
    p.press("backspace")
    check inp.value == "hell"
    check bound == "hell"
    check h.cellAt(1, 5).rune == " ".runeAt(0)
    for col in 1 .. 4:
      check h.cellAt(1, col).rune == bullet

    h.dispose()

  test "password_toggle_off_reveals_value":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "secret", width = 12, border = bsRound,
                     password = true)
      r.appendChild(root, inp.node)
      root)
    let bullet = "\xe2\x80\xa2".runeAt(0)
    check h.cellAt(1, 1).rune == bullet
    inp.setPassword(false)
    h.flush()
    check h.cellAt(1, 1).rune == "s".runeAt(0)
    check h.cellAt(1, 2).rune == "e".runeAt(0)
    h.dispose()
