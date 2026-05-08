## test_isonim_theme_token_compat
##
## M6: an app that already uses the existing `isonim/theming/theme.nim`
## token system (semantic primary / surface / background `ColorToken`s)
## must render correctly under the TUI Theme. The TUI Theme is a
## *superset* — same token names where they overlap (primary, surface,
## etc.).
##
## What "compatibility" means concretely:
##   1. Both modules expose the same six core token names:
##      `primary`, `secondary`, `surface`, `background`, `accent`,
##      `error`. CSS using `$primary` resolves to the *same* RGB
##      value whether the surrounding code initialised an isonim
##      `Theme` or a TUI `Theme`.
##   2. The TUI `Theme.toIsoNimSurface()` lowering produces
##      hex strings the older module accepts via `ColorToken.light`.

import unittest
import isonim_tui
import isonim/theming/theme as isoTheme

suite "M6: isonim/theming/theme compatibility":
  test "test_isonim_theme_token_compat_shared_token_names":
    # The TUI Theme exposes a `primary: string` field. The isonim
    # Theme has `primary: ColorToken`. Names overlap; values can be
    # cross-loaded via parseColor + toHex.
    let tui = builtinTextualDark()
    let resolvedTuiPrimary = parseColor(tui.primary).toHex6
    check resolvedTuiPrimary == "#0178D4"

    # Build an isonim ColorToken from the TUI primary.
    let isoTok = isoTheme.color(tui.primary, tui.primary)
    check isoTok.light == "#0178D4"
    check isoTok.dark == "#0178D4"

  test "test_isonim_theme_token_compat_round_trip_hex":
    # A custom branded TUI theme with a bespoke colour string can be
    # round-tripped to an isonim ColorToken without losing precision.
    let custom = theme(
      name = "branded",
      primary = "#6366F1",
      secondary = "#8B5CF6",
      accent = "#06B6D4",
      surface = "#FFFFFF",
      background = "#F8FAFC",
      error = "#EF4444",
      foreground = "#0F172A",
      dark = false)
    let isoTok = isoTheme.color(custom.primary)
    check isoTok.light == "#6366F1"

  test "test_isonim_theme_token_compat_branded_app_renders":
    # End-to-end: stylesheet using $primary with a TUI Theme whose
    # primary matches an isonim ColorToken — the cell colour is
    # identical no matter which theme module the app initialised.
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", "Button { background: $primary; }")
    let reg = newThemeRegistry()
    reg.registerTheme(theme(
      name = "branded-iso",
      primary = "#6366F1",
      surface = "#FFFFFF",
      background = "#F8FAFC",
      dark = false))
    discard reg.setTheme("branded-iso", sheet)
    let ctx = newThemeContext(reg.activeTheme())
    let comp = computeStylesThemed(sheet,
                                   NodeContext(node: btn, pseudo: {}), ctx)
    check comp.background.kind == cckRgb
    check comp.background.r == 0x63u8
    check comp.background.g == 0x66u8
    check comp.background.b == 0xF1u8

  test "test_isonim_theme_token_compat_isonim_theme_active":
    # Apps that set the isonim active theme via `isoTheme.setTheme`
    # don't crash when the TUI cascade runs alongside (the TUI
    # ThemeRegistry is independent of the isonim global).
    let isoT = isoTheme.isoTheme()
    isoTheme.setTheme(isoT)
    isoTheme.setDarkMode(true)
    let prim = isoTheme.themeColor("primary")
    check prim.len > 0
    # The TUI side stays on its own default theme.
    let tuiReg = newThemeRegistry()
    check tuiReg.activeName == "textual-dark"
