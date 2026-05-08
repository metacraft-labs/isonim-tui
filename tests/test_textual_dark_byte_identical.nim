## test_textual_dark_byte_identical
##
## M6: the `textual-dark` theme values must match `textual/theme.py`
## verbatim — that is the contract that lets a Button rendered under
## IsoNim-TUI snapshot byte-identical to Textual's own snapshot.
##
## The full byte-by-byte snapshot comparison against a real Textual
## install is *deferred*: Textual is not in the dev-shell as of M6.
## What we ship here is a values-check against the published source
## of `textual/theme.py` (commit referenced in the milestone notes).
## When Textual lands as a sibling repo (M23: Textual Compatibility
## Suite), the byte-for-byte snapshot runner will use these same
## values as oracle.

import std/tables
import unittest
import isonim_tui

suite "M6: textual-dark / textual-light parity":
  test "test_textual_dark_byte_identical":
    let dark = builtinTextualDark()
    # Values copied from textual/theme.py (Theme.BUILTIN_THEMES).
    check dark.name == "textual-dark"
    check dark.primary == "#0178D4"
    check dark.secondary == "#004578"
    check dark.accent == "#ffa62b"
    check dark.warning == "#ffa62b"
    check dark.error == "#ba3c5b"
    check dark.success == "#4EBF71"
    check dark.foreground == "#e0e0e0"
    # textual-dark in Textual leaves background/surface/panel unset so
    # ColorSystem's defaults take effect.
    check dark.background == ""
    check dark.surface == ""
    check dark.panel == ""
    check dark.dark == true
    check abs(dark.luminositySpread - 0.15) < 1e-9
    check abs(dark.textAlpha - 0.95) < 1e-9
    check dark.ansi == false
    check dark.variables.len == 0

  test "test_textual_light_byte_identical":
    let light = builtinTextualLight()
    check light.name == "textual-light"
    check light.primary == "#004578"
    check light.secondary == "#0178D4"
    check light.accent == "#ffa62b"
    check light.warning == "#ffa62b"
    check light.error == "#ba3c5b"
    check light.success == "#4EBF71"
    check light.surface == "#D8D8D8"
    check light.panel == "#D0D0D0"
    check light.background == "#E0E0E0"
    check light.dark == false
    check light.variables["footer-key-foreground"] == "#0178D4"

  test "test_builtin_themes_registered":
    let themes = builtinThemes()
    # Every theme that lives in textual/theme.py must be present.
    for n in ["textual-dark", "textual-light", "nord", "gruvbox",
              "dracula", "tokyo-night", "monokai",
              "ansi-dark", "ansi-light"]:
      check n in themes

  test "test_textual_dark_generates_primary_at_0178d4":
    # The generated colour map's `primary` entry should round-trip the
    # input verbatim (lighten(0) on `#0178D4`).
    let dark = builtinTextualDark()
    let colors = dark.generate()
    let primary = parseColor(colors["primary"])
    check primary.r == 0x01u8
    check primary.g == 0x78u8
    check primary.b == 0xD4u8

  test "test_textual_dark_has_dark_default_background":
    let dark = builtinTextualDark()
    let colors = dark.generate()
    # Default dark background lives in design.py: DEFAULT_DARK_BACKGROUND
    # = "#121212".
    let bg = parseColor(colors["background"])
    check bg.r == 0x12u8
    check bg.g == 0x12u8
    check bg.b == 0x12u8

  test "test_ansi_dark_uses_ansi_palette":
    let theme = builtinAnsiDark()
    check theme.ansi == true
    check theme.primary == "ansi_blue"
    let colors = theme.generate()
    # Generated `primary` echoes the parsed ANSI hex (ansi_blue =>
    # rgb(0,0,128) in Textual's COLOR_NAME_TO_RGB).
    check "primary" in colors
