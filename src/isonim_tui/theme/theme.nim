## isonim_tui/theme/theme.nim
##
## Port of `textual/theme.py` (544 LOC).
##
## A `Theme` is a small dataclass: a name plus a set of colour strings
## and a few flags (`dark`, `luminositySpread`, `textAlpha`, `ansi`,
## `variables`). `Theme.toColorSystem()` produces a `ColorSystem` whose
## `generate()` mapping is what the cascade uses to resolve `$primary`,
## `$surface`, `$boost`, etc.
##
## `BUILTIN_THEMES` mirrors `textual/theme.py`'s own dict byte-for-byte;
## the colour values are copied verbatim so apps written for Textual
## render the same way under IsoNim-TUI without theme tweaks.
##
## Integration with `isonim/theming/theme.nim`: that older module is
## token-based (semantic primary/surface ColorTokens) and is used by
## native renderers. This `Theme` is a *superset* with the same
## semantic names where they overlap. `toIsoNimTheme()` lowers a TUI
## Theme into the older shape so Branded UI continues to work.

import std/[tables, algorithm]
import ./design

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  Theme* = object
    ## Mirrors `dataclass Theme` in `textual/theme.py`. Fields are
    ## strings (not parsed `Color`s) because Textual's themes are
    ## defined as literals and we keep the same interface so the
    ## copy-pasted values in `BUILTIN_THEMES` stay byte-identical.
    name*: string
    primary*: string
    secondary*: string
    warning*: string
    error*: string
    success*: string
    accent*: string
    foreground*: string
    background*: string
    surface*: string
    panel*: string
    boost*: string
    dark*: bool
    luminositySpread*: float64
    textAlpha*: float64
    variables*: Table[string, string]
    ansi*: bool
    # Optional ANSI palette override for terminals where the user wants
    # to remap the 16-colour palette.
    ansiPaletteOverride*: Table[string, string]

proc theme*(name, primary: string;
            secondary = ""; warning = ""; error = ""; success = "";
            accent = ""; foreground = ""; background = "";
            surface = ""; panel = ""; boost = "";
            dark = true;
            luminositySpread = 0.15;
            textAlpha = 0.95;
            variables: Table[string, string] = initTable[string, string]();
            ansi = false): Theme =
  Theme(name: name, primary: primary,
        secondary: secondary, warning: warning, error: error,
        success: success, accent: accent, foreground: foreground,
        background: background, surface: surface, panel: panel,
        boost: boost, dark: dark, luminositySpread: luminositySpread,
        textAlpha: textAlpha, variables: variables, ansi: ansi)

proc toColorSystem*(t: Theme): ColorSystem =
  newColorSystem(
    primary = t.primary, secondary = t.secondary, warning = t.warning,
    error = t.error, success = t.success, accent = t.accent,
    foreground = t.foreground, background = t.background,
    surface = t.surface, panel = t.panel, boost = t.boost,
    dark = t.dark, luminositySpread = t.luminositySpread,
    textAlpha = t.textAlpha, variables = t.variables, ansi = t.ansi)

proc generate*(t: Theme): Table[string, string] =
  ## Convenience: parse + generate in one call.
  t.toColorSystem().generate()

# ---------------------------------------------------------------------------
# Built-in themes — byte-identical to textual/theme.py
# ---------------------------------------------------------------------------

proc kv(pairs: openArray[(string, string)]): Table[string, string] =
  result = initTable[string, string]()
  for p in pairs: result[p[0]] = p[1]

proc builtinTextualDark*(): Theme =
  Theme(
    name: "textual-dark",
    primary: "#0178D4",
    secondary: "#004578",
    accent: "#ffa62b",
    warning: "#ffa62b",
    error: "#ba3c5b",
    success: "#4EBF71",
    foreground: "#e0e0e0",
    dark: true,
    luminositySpread: 0.15,
    textAlpha: 0.95,
    variables: initTable[string, string]())

proc builtinTextualLight*(): Theme =
  Theme(
    name: "textual-light",
    primary: "#004578",
    secondary: "#0178D4",
    accent: "#ffa62b",
    warning: "#ffa62b",
    error: "#ba3c5b",
    success: "#4EBF71",
    surface: "#D8D8D8",
    panel: "#D0D0D0",
    background: "#E0E0E0",
    dark: false,
    luminositySpread: 0.15,
    textAlpha: 0.95,
    variables: kv({"footer-key-foreground": "#0178D4"}))

proc builtinNord*(): Theme =
  Theme(
    name: "nord",
    primary: "#88C0D0", secondary: "#81A1C1", accent: "#B48EAD",
    foreground: "#D8DEE9", background: "#2E3440",
    success: "#A3BE8C", warning: "#EBCB8B", error: "#BF616A",
    surface: "#3B4252", panel: "#434C5E",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({
      "block-cursor-background": "#88C0D0",
      "block-cursor-foreground": "#2E3440",
      "block-cursor-text-style": "none",
      "footer-key-foreground": "#88C0D0",
      "input-selection-background": "#81a1c1 35%",
      "button-color-foreground": "#2E3440",
      "button-focus-text-style": "reverse",
    }))

proc builtinGruvbox*(): Theme =
  Theme(
    name: "gruvbox",
    primary: "#85A598", secondary: "#A89A85",
    warning: "#fe8019", error: "#fb4934", success: "#b8bb26",
    accent: "#fabd2f", foreground: "#fbf1c7", background: "#282828",
    surface: "#3c3836", panel: "#504945",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({
      "block-cursor-foreground": "#fbf1c7",
      "input-selection-background": "#689d6a40",
      "button-color-foreground": "#282828",
    }))

proc builtinDracula*(): Theme =
  Theme(
    name: "dracula",
    primary: "#BD93F9", secondary: "#6272A4",
    warning: "#FFB86C", error: "#FF5555", success: "#50FA7B",
    accent: "#FF79C6", background: "#282A36",
    surface: "#2B2E3B", panel: "#313442", foreground: "#F8F8F2",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({"button-color-foreground": "#282A36"}))

proc builtinTokyoNight*(): Theme =
  Theme(
    name: "tokyo-night",
    primary: "#BB9AF7", secondary: "#7AA2F7",
    warning: "#E0AF68", error: "#F7768E", success: "#9ECE6A",
    accent: "#FF9E64", foreground: "#a9b1d6",
    background: "#1A1B26", surface: "#24283B", panel: "#414868",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({"button-color-foreground": "#24283B"}))

proc builtinMonokai*(): Theme =
  Theme(
    name: "monokai",
    primary: "#AE81FF", secondary: "#F92672", accent: "#66D9EF",
    warning: "#FD971F", error: "#F92672", success: "#A6E22E",
    foreground: "#d6d6d6", background: "#272822",
    surface: "#2e2e2e", panel: "#3E3D32",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({
      "foreground-muted": "#797979",
      "input-selection-background": "#575b6190",
      "button-color-foreground": "#272822",
    }))

proc builtinAnsiDark*(): Theme =
  Theme(
    name: "ansi-dark",
    ansi: true,
    primary: "ansi_blue", secondary: "ansi_cyan",
    warning: "ansi_yellow", error: "ansi_red",
    success: "ansi_green", accent: "ansi_green",
    foreground: "ansi_default", background: "ansi_default",
    surface: "ansi_default", panel: "ansi_default", boost: "ansi_default",
    dark: true, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({
      "ansi-background": "ansi_black",
      "ansi-foreground": "ansi_white",
      "border-blurred": "ansi_black",
      "block-cursor-foreground": "ansi_black",
      "block-cursor-background": "ansi_white",
      "input-cursor-background": "ansi_black",
      "input-cursor-foreground": "ansi_bright_white",
      "input-cursor-text-style": "none",
      "input-selection-background": "ansi_bright_blue",
      "input-selection-foreground": "ansi_black",
      "screen-selection-background": "ansi_bright_blue",
      "screen-selection-foreground": "ansi_black",
    }))

proc builtinAnsiLight*(): Theme =
  Theme(
    name: "ansi-light",
    ansi: true,
    primary: "ansi_blue", secondary: "ansi_cyan",
    warning: "ansi_bright_red", error: "ansi_red",
    success: "ansi_green", accent: "ansi_magenta",
    foreground: "ansi_default", background: "ansi_default",
    surface: "ansi_default", panel: "ansi_default", boost: "ansi_default",
    dark: false, luminositySpread: 0.15, textAlpha: 0.95,
    variables: kv({
      "border": "ansi_blue",
      "border-blurred": "ansi_white",
      "block-cursor-foreground": "ansi_bright_white",
      "block-cursor-background": "ansi_blue",
      "ansi-background": "ansi_white",
      "ansi-foreground": "ansi_black",
      "input-cursor-background": "ansi_bright_white",
      "input-cursor-foreground": "ansi_black",
      "input-cursor-text-style": "reverse",
      "input-selection-background": "ansi_cyan",
      "input-selection-foreground": "ansi_white",
      "scrollbar": "ansi_bright_blue",
      "scrollbar-hover": "ansi_blue",
      "scrollbar-active": "ansi_blue",
      "scrollbar-background": "ansi_white",
      "scrollbar-corner-color": "ansi_default",
      "scrollbar-background-hover": "ansi_white",
      "scrollbar-background-active": "ansi_white",
      "block-hover-background": "ansi_white",
      "screen-selection-background": "ansi_cyan",
      "screen-selection-foreground": "ansi_bright_white",
    }))

proc builtinThemes*(): Table[string, Theme] =
  ## Map of every built-in theme. Order matches `textual/theme.py`.
  result = initTable[string, Theme]()
  result["textual-dark"] = builtinTextualDark()
  result["textual-light"] = builtinTextualLight()
  result["nord"] = builtinNord()
  result["gruvbox"] = builtinGruvbox()
  result["dracula"] = builtinDracula()
  result["tokyo-night"] = builtinTokyoNight()
  result["monokai"] = builtinMonokai()
  result["ansi-dark"] = builtinAnsiDark()
  result["ansi-light"] = builtinAnsiLight()

proc builtinThemeNames*(): seq[string] =
  ## Sorted names — used by the command palette.
  for k in builtinThemes().keys: result.add(k)
  result.sort()

# ---------------------------------------------------------------------------
# CSS-variable resolution
# ---------------------------------------------------------------------------

proc resolveVariables*(t: Theme): Table[string, string] =
  ## Generate the full `$variable` → CSS-string map for the active
  ## theme. Includes user overrides via `t.variables`. Keys are stored
  ## *without* a leading `$` — the cascade strips that before lookup.
  t.generate()

proc isDarkTheme*(t: Theme): bool {.inline.} = t.dark
proc isLightTheme*(t: Theme): bool {.inline.} = not t.dark
