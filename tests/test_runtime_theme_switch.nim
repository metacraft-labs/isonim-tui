## test_runtime_theme_switch
##
## M6: switching themes at runtime invalidates the per-widget styles
## cache and triggers a fresh cascade. The next computed style for any
## widget that depends on a theme variable picks up the new colour.

import unittest
import isonim_tui

suite "M6: runtime theme switching":
  test "test_runtime_theme_switch":
    # Build a small DOM and a stylesheet that uses $primary.
    let r = TerminalRenderer()
    let root = r.createElement("Screen")
    r.setAttribute(root, "id", "app")
    let btn = r.createElement("Button")
    r.setAttribute(btn, "id", "submit")
    r.appendChild(root, btn)

    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { background: $primary; }
    """)

    let reg = newThemeRegistry()
    # Active theme = textual-dark (primary #0178D4).
    var ctx = newThemeContext(reg.activeTheme())
    let nodeCtx = NodeContext(node: btn, pseudo: {})
    let computedDark = computeStylesThemed(sheet, nodeCtx, ctx)

    check computedDark.background.kind == cckRgb
    check computedDark.background.r == 0x01u8
    check computedDark.background.g == 0x78u8
    check computedDark.background.b == 0xD4u8

    # Switch to textual-light (primary #004578).
    let ok = reg.setTheme("textual-light", sheet)
    check ok
    ctx = newThemeContext(reg.activeTheme())
    let computedLight = computeStylesThemed(sheet, nodeCtx, ctx)
    check computedLight.background.kind == cckRgb
    check computedLight.background.r == 0x00u8
    check computedLight.background.g == 0x45u8
    check computedLight.background.b == 0x78u8
    # The stylesheet revision was bumped, so any cached styles are
    # invalid → the fresh cascade returns the new colour.
    check sheet.revision == 2  # one for addCss, one for setTheme

  test "test_runtime_theme_switch_unknown_theme_returns_false":
    let reg = newThemeRegistry()
    check reg.setTheme("does-not-exist") == false
    check reg.activeName == "textual-dark"

  test "test_runtime_theme_switch_subscribers_fire":
    let reg = newThemeRegistry()
    var fired = 0
    var lastName = ""
    reg.subscribe(proc(t: Theme) =
      inc fired
      lastName = t.name)
    discard reg.setTheme("textual-light")
    check fired == 1
    check lastName == "textual-light"

  test "test_runtime_theme_switch_idempotent":
    let reg = newThemeRegistry()
    var fired = 0
    reg.subscribe(proc(t: Theme) {.closure.} = inc fired)
    # Setting the same theme twice fires only once (or zero, since the
    # implementation early-returns when already active).
    discard reg.setTheme("textual-dark")
    discard reg.setTheme("textual-dark")
    check fired == 0  # no change ⇒ no callback

  test "test_runtime_theme_switch_dozen_widgets_all_change":
    # Mount many widgets, all consume $primary; switching theme
    # changes every widget's computed colour.
    let r = TerminalRenderer()
    let root = r.createElement("Screen")
    var widgets: seq[TerminalNode]
    for i in 0..<12:
      let n = r.createElement("Button")
      r.setAttribute(n, "id", "btn" & $i)
      r.appendChild(root, n)
      widgets.add(n)

    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", "Button { background: $primary; }")

    let reg = newThemeRegistry()
    var ctx = newThemeContext(reg.activeTheme())

    var darkColors: seq[CssColor]
    for w in widgets:
      let c = computeStylesThemed(sheet,
                                  NodeContext(node: w, pseudo: {}), ctx)
      darkColors.add(c.background)
    for c in darkColors:
      check c.r == 0x01u8

    discard reg.setTheme("textual-light", sheet)
    ctx = newThemeContext(reg.activeTheme())
    for w in widgets:
      let c = computeStylesThemed(sheet,
                                  NodeContext(node: w, pseudo: {}), ctx)
      # Every widget now resolves to the light primary.
      check c.background.r == 0x00u8
      check c.background.g == 0x45u8
      check c.background.b == 0x78u8
