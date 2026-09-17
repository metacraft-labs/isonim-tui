## test_css_cascade_reaches_compositor
##
## The TCSS cascade (`css/*`, `theme/cascade.nim`) computes a fully
## resolved `Styles` for any node. For a long time nothing on a painting
## path ever called it: `newStylesheet` had exactly one reference in
## `src/` — its own definition — and the compositor painted from the
## inline `node.styles` table that widgets write directly.
##
## The visible consequence was that `:disabled` had no rendering at all.
## `m12_button_default` and `m12_button_disabled` were byte-identical in
## all six golden formats, because the engine that would have given
## `:disabled` a look was unreachable.
##
## These tests assert against *painted cells* — `h.cellAt(row, col)` —
## not against `computeStyles` return values. A test that only checks the
## cascade's output would have passed throughout the entire period the
## cascade was unreachable, which is precisely the failure mode being
## closed here.

import std/tables
import unittest
import isonim_tui

# The button is mounted at row 0; row 1 is the label row `│   OK   │`,
# so column 4 is inside the label and column 0 is the left border.
const labelRow = 1
const labelCol = 4

proc mountButton(h: TerminalTestHarness; disabled: bool) =
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let b = newButton(r, "OK", width = 8, disabled = disabled)
    r.appendChild(root, b.node)
    root)

suite "M5/M6: the cascade reaches the compositor":

  test "a stylesheet rule changes a painted cell":
    # The floor: without this, nothing else in this file can hold.
    let h = newTerminalTestHarness(20, 4)
    h.mountButton(disabled = false)

    let before = h.cellAt(labelRow, labelCol)
    check before.fg.kind == ckDefault

    h.addCss("Button { color: #00ff00; }")

    let after = h.cellAt(labelRow, labelCol)
    check after.fg.kind == ckRgb
    check after.fg.r == 0x00u8
    check after.fg.g == 0xFFu8
    check after.fg.b == 0x00u8
    h.dispose()

  test "disabled renders differently from default":
    # The falsifiable consequence of the fix. Both harnesses get the
    # *same* stylesheet; the only difference is the `disabled`
    # attribute, and therefore the `:disabled` pseudo-state.
    const css = """
      Button { color: #00ff00; }
      Button:disabled { color: #808080; text-style: dim; }
    """

    let hDefault = newTerminalTestHarness(20, 4)
    hDefault.mountButton(disabled = false)
    hDefault.addCss(css)

    let hDisabled = newTerminalTestHarness(20, 4)
    hDisabled.mountButton(disabled = true)
    hDisabled.addCss(css)

    let normal = hDefault.cellAt(labelRow, labelCol)
    let dimmed = hDisabled.cellAt(labelRow, labelCol)

    # The states must not be identical — the whole defect was that they
    # were. Assert the specific difference, not merely inequality, so a
    # future regression that changes both in lockstep still fails.
    check normal.fg.kind == ckRgb
    check normal.fg.g == 0xFFu8
    check attrDim notin normal.attrs

    check dimmed.fg.kind == ckRgb
    check dimmed.fg.r == 0x80u8
    check dimmed.fg.g == 0x80u8
    check dimmed.fg.b == 0x80u8
    check attrDim in dimmed.attrs

    check normal != dimmed
    hDefault.dispose()
    hDisabled.dispose()

  test "the whole painted buffer differs between default and disabled":
    # Cell-level equality is the sharp assertion above; this one guards
    # the same property at the granularity the m12 goldens record, so a
    # regression shows up as a snapshot-shaped difference too.
    const css = "Button:disabled { color: #808080; }"

    let hDefault = newTerminalTestHarness(20, 4)
    hDefault.mountButton(disabled = false)
    hDefault.addCss(css)

    let hDisabled = newTerminalTestHarness(20, 4)
    hDisabled.mountButton(disabled = true)
    hDisabled.addCss(css)

    check encodeCellMap(hDefault.screenBuffer) !=
          encodeCellMap(hDisabled.screenBuffer)
    hDefault.dispose()
    hDisabled.dispose()

  test "focus and hover pseudo-states reach painted cells":
    const css = """
      Button { color: #101010; }
      Button:focus { color: #ff0000; }
      Button:hover { color: #0000ff; }
    """
    let h = newTerminalTestHarness(20, 4)
    var b: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b = newButton(r, "OK", width = 8)
      r.appendChild(root, b.node)
      root)
    h.addCss(css)
    check h.cellAt(labelRow, labelCol).fg.r == 0x10u8

    let p = newPilot(h)
    p.focus(b.node)
    check h.cellAt(labelRow, labelCol).fg.r == 0xFFu8
    check h.cellAt(labelRow, labelCol).fg.b == 0x00u8

    p.hover(b.node)
    check h.cellAt(labelRow, labelCol).fg.b == 0xFFu8
    h.dispose()

  test "inline styles beat cascaded ones":
    # CSS precedence: a value written through `setStyle` is an inline
    # style and must survive the materialisation pass.
    let h = newTerminalTestHarness(20, 4)
    var target: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let b = newButton(r, "OK", width = 8)
      target = b.node
      r.setStyle(b.node, "color", "#123456")
      r.appendChild(root, b.node)
      root)
    h.addCss("Button { color: #00ff00; }")

    let c = h.cellAt(labelRow, labelCol)
    check c.fg.r == 0x12u8
    check c.fg.g == 0x34u8
    check c.fg.b == 0x56u8
    check target.styles["color"] == "#123456"
    h.dispose()

  test "a repaint retracts a rule that no longer matches":
    # The engine records what it wrote so the next pass can retract it.
    # Losing focus must take the focus colour with it.
    const css = """
      Button { color: #101010; }
      Button:focus { color: #ff0000; }
    """
    let h = newTerminalTestHarness(20, 4)
    var b: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b = newButton(r, "OK", width = 8)
      r.appendChild(root, b.node)
      root)
    h.addCss(css)
    let p = newPilot(h)
    p.focus(b.node)
    check h.cellAt(labelRow, labelCol).fg.r == 0xFFu8
    h.focusManager.clearFocus(h.root)
    h.focusedId = 0
    h.flush()
    check h.cellAt(labelRow, labelCol).fg.r == 0x10u8
    h.dispose()

  test "no stylesheet means no mutation":
    # The pass must be a strict no-op for an app that registers no CSS,
    # otherwise every pre-existing golden in tests/snapshots/ would move.
    let h = newTerminalTestHarness(20, 4)
    var target: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let b = newButton(r, "OK", width = 8)
      target = b.node
      r.appendChild(root, b.node)
      root)
    check not h.styleEngine.hasStyles()
    check target.styles.len == 0
    check h.cellAt(labelRow, labelCol).fg.kind == ckDefault
    h.dispose()

suite "M6: runtime theme switch repaints":

  test "setTheme repaints cells that resolve a theme variable":
    # `ThemeRegistry.setTheme` bumping a revision was the whole of M6
    # before this: there was no `h.setTheme`, and no test mounted a
    # harness or read a cell. This one does both.
    let h = newTerminalTestHarness(20, 4)
    h.mountButton(disabled = false)
    h.addCss("Button { color: $primary; }")

    # textual-dark's $primary is #0178D4.
    let dark = h.cellAt(labelRow, labelCol)
    check h.activeThemeName == "textual-dark"
    check dark.fg.kind == ckRgb
    check dark.fg.r == 0x01u8
    check dark.fg.g == 0x78u8
    check dark.fg.b == 0xD4u8

    check h.setTheme("textual-light")

    # textual-light's $primary is #004578.
    let light = h.cellAt(labelRow, labelCol)
    check h.activeThemeName == "textual-light"
    check light.fg.kind == ckRgb
    check light.fg.r == 0x00u8
    check light.fg.g == 0x45u8
    check light.fg.b == 0x78u8

    check dark != light
    h.dispose()

  test "an unknown theme name repaints nothing and returns false":
    let h = newTerminalTestHarness(20, 4)
    h.mountButton(disabled = false)
    h.addCss("Button { color: $primary; }")
    let before = h.cellAt(labelRow, labelCol)
    check h.setTheme("does-not-exist") == false
    check h.cellAt(labelRow, labelCol) == before
    check h.activeThemeName == "textual-dark"
    h.dispose()

  test "@dark and @light rules paint according to the active theme":
    let h = newTerminalTestHarness(20, 4)
    h.mountButton(disabled = false)
    h.addCss("""
      @dark  Button { color: #ff0000; }
      @light Button { color: #00ff00; }
    """)
    check h.cellAt(labelRow, labelCol).fg.r == 0xFFu8
    check h.setTheme("textual-light")
    check h.cellAt(labelRow, labelCol).fg.g == 0xFFu8
    h.dispose()
