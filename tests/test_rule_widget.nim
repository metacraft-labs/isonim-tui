## test_rule_widget — M11 widget snapshot coverage.
##
## Verifies the `Rule` widget paints horizontal and vertical
## separator lines with the configured `BorderStyle` glyph. The
## snapshot covers both orientations.

import unittest
import std/unicode
import isonim_tui

suite "M11: Rule widget":
  test "test_rule_horizontal_solid":
    let h = newTerminalTestHarness(12, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roHorizontal,
                         width = 10, style = bsSolid)
      r.appendChild(root, rule.node)
      root)
    # Each of columns 0..9 shows the horizontal solid glyph ─.
    for col in 0 ..< 10:
      check h.cellAt(0, col).rune == "─".runeAt(0)
    # Column 10 is empty padding from the row fill.
    check h.cellAt(0, 10).rune == Rune(' '.ord)

    discard h.snap("m11_rule_horizontal_solid")
    h.dispose()

  test "test_rule_horizontal_double":
    let h = newTerminalTestHarness(12, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roHorizontal,
                         width = 8, style = bsDouble)
      r.appendChild(root, rule.node)
      root)
    for col in 0 ..< 8:
      check h.cellAt(0, col).rune == "═".runeAt(0)

    discard h.snap("m11_rule_horizontal_double")
    h.dispose()

  test "test_rule_vertical_heavy":
    let h = newTerminalTestHarness(8, 4)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roVertical,
                         height = 3, style = bsHeavy)
      r.appendChild(root, rule.node)
      root)
    for row in 0 ..< 3:
      check h.cellAt(row, 0).rune == "┃".runeAt(0)

    discard h.snap("m11_rule_vertical_heavy")
    h.dispose()

  test "test_rule_horizontal_ascii":
    let h = newTerminalTestHarness(12, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roHorizontal,
                         width = 6, style = bsAscii)
      r.appendChild(root, rule.node)
      root)
    for col in 0 ..< 6:
      check h.cellAt(0, col).rune == Rune('-'.ord)
    h.dispose()
