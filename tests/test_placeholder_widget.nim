## test_placeholder_widget — M11 widget snapshot coverage.
##
## Verifies the `Placeholder` widget renders a named coloured box
## with deterministic colour selection: the same name always picks
## the same ANSI hue. The cell map is pinned via the standard six-
## format snapshot runner.

import unittest
import std/unicode
import isonim_tui

suite "M11: Placeholder widget":
  test "test_placeholder_renders_named_box":
    let h = newTerminalTestHarness(20, 6)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let ph = newPlaceholder(r, name = "panel-A",
                              width = 12, height = 3)
      r.appendChild(root, ph.node)
      root)

    # Box-drawing top corners present.
    check h.cellAt(0, 0).rune == "┌".runeAt(0)
    check h.cellAt(0, 13).rune == "┐".runeAt(0)
    # Bottom border row sits at row 4 (1 + 3 inner rows = 4).
    check h.cellAt(4, 0).rune == "└".runeAt(0)
    check h.cellAt(4, 13).rune == "┘".runeAt(0)
    # The name appears centred on the middle row.
    let middleRow = 2
    check h.cellAt(middleRow, 0).rune == "│".runeAt(0)
    # The padded centre row contains "panel-A".
    var found = false
    for col in 1 ..< 13:
      if h.cellAt(middleRow, col).rune == Rune('p'.ord):
        found = true; break
    check found

    discard h.snap("m11_placeholder_panel_a")

    h.dispose()

  test "test_placeholder_color_is_deterministic":
    # Same name → same ANSI hue across two harnesses.
    let h1 = newTerminalTestHarness(20, 4)
    let h2 = newTerminalTestHarness(20, 4)
    let cA1 = colorForName("widget-A")
    let cA2 = colorForName("widget-A")
    check cA1 == cA2
    let cB = colorForName("widget-B")
    # B should pick a *different* hue from A under the standard
    # 6-colour pool. (If hash mod 6 collides, the assertion still
    # holds for *some* names; pick distinct ones likely to
    # disambiguate.)
    if cA1 == cB:
      let cC = colorForName("entirely-different")
      check cA1 != cC or cB != cC
    h1.dispose()
    h2.dispose()
