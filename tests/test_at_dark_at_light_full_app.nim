## test_at_dark_at_light_full_app
##
## M6: stylesheet rules tagged with `@dark` / `@light` apply only when
## the active theme matches that polarity. The cascade gates them via
## the `ThemeContext.isDark` flag.

import unittest
import isonim_tui

suite "M6: @dark / @light gating":
  test "test_at_dark_block_applies_in_dark_theme":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { background: white; color: black; }
      @dark Button { background: black; color: white; }
      @light Button { background: white; color: black; }
    """)
    let nodeCtx = NodeContext(node: btn, pseudo: {})

    # Under textual-dark: @dark wins (later in source than the base
    # rule), background becomes black.
    let darkCtx = newThemeContext(builtinTextualDark())
    let computedDark = computeStylesThemed(sheet, nodeCtx, darkCtx)
    check computedDark.background.kind == cckNamed
    check computedDark.background.name == "black"

    # Under textual-light: @light wins, background stays white.
    let lightCtx = newThemeContext(builtinTextualLight())
    let computedLight = computeStylesThemed(sheet, nodeCtx, lightCtx)
    check computedLight.background.kind == cckNamed
    check computedLight.background.name == "white"

  test "test_at_light_block_filtered_out_in_dark_theme":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    # Only an @light rule. Under @dark, no rule matches; the cascade
    # leaves background at its default (transparent).
    sheet.addCss(ssUser, "app.tcss", """
      @light Button { background: red; }
    """)
    let darkCtx = newThemeContext(builtinTextualDark())
    let computed = computeStylesThemed(sheet,
                                       NodeContext(node: btn, pseudo: {}),
                                       darkCtx)
    check not computed.backgroundSet

  test "test_dark_only_rule_applies_in_dark_theme_only":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      @dark Button { background: red; }
    """)
    let darkComputed = computeStylesThemed(
      sheet, NodeContext(node: btn, pseudo: {}),
      newThemeContext(builtinTextualDark()))
    check darkComputed.backgroundSet
    check darkComputed.background.name == "red"

    let lightComputed = computeStylesThemed(
      sheet, NodeContext(node: btn, pseudo: {}),
      newThemeContext(builtinTextualLight()))
    check not lightComputed.backgroundSet

  test "test_at_dark_at_light_full_app":
    # Realistic app: a base rule plus polarity-specific overrides for
    # text colour. Snapshot equivalence: the values cascade correctly
    # under both themes.
    let r = TerminalRenderer()
    let label = r.createElement("Label")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Label { color: white; background: black; }
      @dark Label { color: white; }
      @light Label { color: black; background: white; }
    """)
    let darkCtx = newThemeContext(builtinTextualDark())
    let lightCtx = newThemeContext(builtinTextualLight())
    let lblCtx = NodeContext(node: label, pseudo: {})

    let darkComp = computeStylesThemed(sheet, lblCtx, darkCtx)
    let lightComp = computeStylesThemed(sheet, lblCtx, lightCtx)

    check darkComp.color.name == "white"
    check darkComp.background.name == "black"

    check lightComp.color.name == "black"
    check lightComp.background.name == "white"
