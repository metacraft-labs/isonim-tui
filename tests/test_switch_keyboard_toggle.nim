## test_switch_keyboard_toggle — M12 mandatory test.
##
## `Space` on a focused switch flips its bound signal; visual state
## updates; cell-map snapshot confirms the rune at the switch's
## position changed.

import unittest
import std/unicode
import isonim_tui

suite "M12: switch keyboard toggle":
  test "test_switch_keyboard_toggle":
    let h = newTerminalTestHarness(30, 3)
    var sw: SwitchWidget
    var lastValue = false
    var changeCount = 0
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sw = newSwitch(r, value = false,
                     onChange = proc(v: bool) =
                       lastValue = v
                       inc changeCount)
      r.appendChild(root, sw.node)
      root)

    # Initially off; rune at col 1 is the left dot ●.
    check sw.value == false
    let initialMidRune = h.cellAt(0, 1).rune
    check initialMidRune == "●".runeAt(0)

    # Right-side rune is the centre dot.
    let initialRightRune = h.cellAt(0, 2).rune
    check initialRightRune == "·".runeAt(0)

    let p = newPilot(h)
    p.focus(sw.node)

    # Space toggles to on.
    p.press("space")
    check sw.value == true
    check lastValue == true
    check changeCount == 1

    # Visual updated: now col 1 is the dot, col 2 is the on-position.
    check h.cellAt(0, 1).rune == "·".runeAt(0)
    check h.cellAt(0, 2).rune == "●".runeAt(0)

    # Press again: back to off.
    p.press("space")
    check sw.value == false
    check changeCount == 2

    # Visual reverts.
    check h.cellAt(0, 1).rune == "●".runeAt(0)
    check h.cellAt(0, 2).rune == "·".runeAt(0)

    h.dispose()

  test "switch_disabled_does_not_toggle":
    let h = newTerminalTestHarness(30, 3)
    var sw: SwitchWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sw = newSwitch(r, value = false, disabled = true)
      r.appendChild(root, sw.node)
      root)
    let p = newPilot(h)
    p.focus(sw.node)
    p.press("space")
    check sw.value == false
    h.dispose()
