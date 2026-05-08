## isonim_tui/theme/design.nim
##
## Port of `textual/design.py` (~559 LOC). The `ColorSystem` takes a
## handful of base colours (primary, secondary, …) and *generates* a
## flat name → CSS-string mapping that Textual's themes consume.
##
## Generated names follow the `<color>[-<lighten|darken>-N]` shape, e.g.
## `primary`, `primary-darken-1`, `primary-lighten-2`. Three shades on
## each side, default `luminosity_spread = 0.15` (so darken-2 is 15%
## darker, darken-3 is 22.5% darker).
##
## Charter: this module produces a `Table[string, string]` that the
## stylesheet's `$primary` variable resolution feeds from. No widget
## code calls into here directly.

import std/tables
import ./color

const
  NumberOfShades* = 3

  DefaultDarkBackground* = "#121212"
  DefaultDarkSurface* = "#1e1e1e"
  DefaultLightSurface* = "#f5f5f5"
  DefaultLightBackground* = "#efefef"

const ColorNames* = [
  "primary",
  "secondary",
  "background",
  "primary-background",
  "secondary-background",
  "surface",
  "panel",
  "boost",
  "warning",
  "error",
  "success",
  "accent",
]

const ShadeColors = [
  "primary",
  "secondary",
  "primary-background",
  "secondary-background",
  "background",
  "foreground",
  "panel",
  "boost",
  "surface",
  "warning",
  "error",
  "success",
  "accent",
]

type
  ColorSystem* = object
    ## Mirror of Textual's `ColorSystem`. Every base colour is held as a
    ## parsed `Color`; nil-equivalent inputs are recorded by `<name>Set`
    ## flags so `_generate` can reproduce Python's "if not set,
    ## fall-back-to-X" branches.
    primary*: Color
    secondary*: Color
    secondarySet*: bool
    warning*: Color
    warningSet*: bool
    error*: Color
    errorSet*: bool
    success*: Color
    successSet*: bool
    accent*: Color
    accentSet*: bool
    foreground*: Color
    foregroundSet*: bool
    background*: Color
    backgroundSet*: bool
    surface*: Color
    surfaceSet*: bool
    panel*: Color
    panelSet*: bool
    boost*: Color
    boostSet*: bool
    dark*: bool
    luminositySpread*: float64
    textAlpha*: float64
    variables*: Table[string, string]
    ansi*: bool

proc newColorSystem*(
    primary: string;
    secondary = ""; warning = ""; error = ""; success = ""; accent = "";
    foreground = ""; background = ""; surface = ""; panel = ""; boost = "";
    dark = false; luminositySpread = 0.15; textAlpha = 0.95;
    variables: Table[string, string] = initTable[string, string]();
    ansi = false): ColorSystem =
  ## Construct a ColorSystem. Empty-string args mean "not set" (Textual's
  ## `Optional[str]` semantics).
  result.primary = parseColor(primary)
  if secondary.len > 0:
    result.secondary = parseColor(secondary); result.secondarySet = true
  if warning.len > 0:
    result.warning = parseColor(warning); result.warningSet = true
  if error.len > 0:
    result.error = parseColor(error); result.errorSet = true
  if success.len > 0:
    result.success = parseColor(success); result.successSet = true
  if accent.len > 0:
    result.accent = parseColor(accent); result.accentSet = true
  if foreground.len > 0:
    result.foreground = parseColor(foreground); result.foregroundSet = true
  if background.len > 0:
    result.background = parseColor(background); result.backgroundSet = true
  if surface.len > 0:
    result.surface = parseColor(surface); result.surfaceSet = true
  if panel.len > 0:
    result.panel = parseColor(panel); result.panelSet = true
  if boost.len > 0:
    result.boost = parseColor(boost); result.boostSet = true
  result.dark = dark
  result.luminositySpread = luminositySpread
  result.textAlpha = textAlpha
  result.variables = variables
  result.ansi = ansi

proc shades*(sys: ColorSystem): seq[string] =
  ## Names of every colour and derived shade. Used by tests and the
  ## debug "design" inspector.
  for c in ColorNames:
    for n in -NumberOfShades .. NumberOfShades:
      if n < 0:
        result.add(c & "-darken-" & $abs(n))
      elif n > 0:
        result.add(c & "-lighten-" & $n)
      else:
        result.add(c)

proc getOrDefault(sys: ColorSystem; name, default: string): string {.inline.} =
  if name in sys.variables: sys.variables[name]
  else: default

iterator luminosityRange(spread: float64): (string, float64) =
  ## Mirror of Textual's `luminosity_range(spread)`.
  let step = spread / 2.0
  for n in -NumberOfShades .. NumberOfShades:
    let label =
      if n < 0: "-darken"
      elif n > 0: "-lighten"
      else: ""
    let suffix =
      if n != 0: label & "-" & $abs(n)
      else: ""
    yield (suffix, n.float64 * step)

# ---------------------------------------------------------------------------
# ANSI generator (matches Textual's `_generate_ansi`)
# ---------------------------------------------------------------------------

proc generateAnsi*(sys: ColorSystem): Table[string, string] =
  let primary = sys.primary
  let secondary = if sys.secondarySet: sys.secondary else: primary
  let warning = if sys.warningSet: sys.warning else: primary
  let errorC = if sys.errorSet: sys.error else: secondary
  let success = if sys.successSet: sys.success else: secondary
  let accent = if sys.accentSet: sys.accent else: primary

  let background =
    if not sys.backgroundSet: "ansi_default"
    else: sys.background.toHex
  let foreground =
    if not sys.foregroundSet: "ansi_default"
    else: sys.foreground.toHex

  result = {
    "primary": primary.toHex,
    "secondary": secondary.toHex,
    "warning": warning.toHex,
    "error": errorC.toHex,
    "success": success.toHex,
    "accent": accent.toHex,
    "background": background,
    "foreground": foreground,
    "primary-background": background,
    "secondary-background": background,
    "boost": "transparent",
    "surface": "transparent",
    "text": "ansi_default",
    "text-muted": "ansi_default 50%",
    "text-disabled": "ansi_default 50%",
    "text-primary": primary.toHex,
    "text-secondary": secondary.toHex,
    "text-warning": warning.toHex,
    "text-error": errorC.toHex,
    "text-success": success.toHex,
    "text-accent": accent.toHex,
    "panel": "transparent",
    "primary-muted": primary.toHex & " 50%",
    "secondary-muted": secondary.toHex & " 50%",
    "warning-muted": warning.toHex & " 50%",
    "error-muted": errorC.toHex & " 50%",
    "success-muted": success.toHex & " 50%",
    "accent-muted": accent.toHex & " 50%",
    "foreground-muted": "ansi_default 50%",
    "background-muted": "ansi_default 50%",
    "block-cursor-foreground": "ansi_default",
    "block-cursor-background": "ansi_magenta",
    "block-cursor-text-style": "bold",
    "block-cursor-blurred-foreground": "ansi_default",
    "block-cursor-blurred-background": "ansi_default",
    "block-cursor-blurred-text-style": "none",
    "block-hover-background": "ansi_default",
    "border": "ansi_magenta",
    "border-blurred": "ansi_black",
    "surface-actrive": "transparent",
    "scrollbar": "ansi_blue",
    "scrollbar-hover": "ansi_blue",
    "scrollbar-active": "ansi_bright_blue",
    "scrollbar-background": "ansi_black",
    "scrollbar-corner-color": "ansi_default",
    "scrollbar-background-hover": "ansi_black",
    "scrollbar-background-active": "ansi_black",
    "link-style": "underline",
    "link-background": "transparent",
    "link-background-hover": "ansi_bright_blue",
    "link-color": "ansi_blue",
    "link-color-hover": "ansi_bright_white",
    "link-style-hover": "not underline",
    "footer-foreground": "ansi_default",
    "footer-background": "ansi_default",
    "footer-key-foreground": "ansi_magenta",
    "footer-key-background": "transparent",
    "footer-description-foreground": "ansi_default",
    "footer-description-background": "ansi_default",
    "footer-item-background": "ansi_default",
    "input-cursor-background": "ansi_default",
    "input-cursor-foreground": "ansi_default",
    "input-cursor-text-style": "reverse",
    "input-selection-background": "ansi_cyan",
    "input-selection-foreground": "ansi_default",
    "markdown-h1-color": "ansi_magenta",
    "markdown-h1-background": "transparent",
    "markdown-h1-text-style": "bold",
    "markdown-h2-color": "ansi_bright_blue",
    "markdown-h2-background": "transparent",
    "markdown-h2-text-style": "underline",
    "markdown-h3-color": "ansi_blue",
    "markdown-h3-background": "transparent",
    "markdown-h3-text-style": "none",
    "markdown-h4-color": "ansi_cyan",
    "markdown-h4-background": "transparent",
    "markdown-h4-text-style": "bold",
    "markdown-h5-color": "ansi_cyan",
    "markdown-h5-background": "transparent",
    "markdown-h5-text-style": "none",
    "markdown-h6-color": "ansi_cyan",
    "markdown-h6-background": "transparent",
    "markdown-h6-text-style": "underline",
    "button-foreground": "ansi_default",
    "button-color-foreground": "ansi_default",
    "button-focus-text-style": "b reverse",
    "screen-selection-background": "ansi_cyan",
    "screen-selection-foreground": "ansi_black",
  }.toTable

  # Shade colours: ANSI just echoes the base colour at every shade.
  for shade in 1 .. NumberOfShades:
    for cName in ShadeColors:
      if cName notin result: continue
      result[cName & "-lighten-" & $shade] = result[cName]
      result[cName & "-darken-" & $shade] = result[cName]

  # User overrides win.
  for k, v in sys.variables:
    result[k] = v

# ---------------------------------------------------------------------------
# Standard generator (`_generate`)
# ---------------------------------------------------------------------------

proc generate*(sys: ColorSystem): Table[string, string] =
  ## Mirror of Textual's `_generate`. Returns a name → CSS-string
  ## mapping for every theme variable.
  if sys.ansi:
    return generateAnsi(sys)

  let primary = sys.primary
  let secondary = if sys.secondarySet: sys.secondary else: primary
  let warning = if sys.warningSet: sys.warning else: primary
  let errorC = if sys.errorSet: sys.error else: secondary
  let success = if sys.successSet: sys.success else: secondary
  let accent = if sys.accentSet: sys.accent else: primary

  let dark = sys.dark
  let luminositySpread = sys.luminositySpread

  result = initTable[string, string]()

  let background =
    if sys.backgroundSet: sys.background
    elif dark: parseColor(DefaultDarkBackground)
    else: parseColor(DefaultLightBackground)

  let surface =
    if sys.surfaceSet: sys.surface
    elif dark: parseColor(DefaultDarkSurface)
    else: parseColor(DefaultLightSurface)

  let foreground =
    if sys.foregroundSet: sys.foreground
    else: background.inverse

  var boost: Color = transparent()
  var panel: Color

  if background.kind == cckAnsi:
    result["text-primary"] = primary.toHex
    result["text-secondary"] = secondary.toHex
    result["text-warning"] = warning.toHex
    result["text-error"] = errorC.toHex
    result["text-success"] = success.toHex
    result["text-accent"] = accent.toHex
    panel = if sys.panelSet: sys.panel else: transparent()
  else:
    let contrastText = background.getContrastText(1.0)
    result["text-primary"] = contrastText.tint(primary.withAlpha(0.66)).toHex
    result["text-secondary"] = contrastText.tint(secondary.withAlpha(0.66)).toHex
    result["text-warning"] = contrastText.tint(warning.withAlpha(0.66)).toHex
    result["text-error"] = contrastText.tint(errorC.withAlpha(0.66)).toHex
    result["text-success"] = contrastText.tint(success.withAlpha(0.66)).toHex
    result["text-accent"] = contrastText.tint(accent.withAlpha(0.66)).toHex

    if not sys.panelSet:
      panel = surface.blend(primary, 0.1, 1.0)
      if dark:
        boost = if sys.boostSet: sys.boost else: contrastText.withAlpha(0.04)
        panel = panel + boost
    else:
      panel = sys.panel

  let colorPairs: seq[(string, Color)] = @[
    ("primary", primary),
    ("secondary", secondary),
    ("primary-background", primary),
    ("secondary-background", secondary),
    ("background", background),
    ("foreground", foreground),
    ("panel", panel),
    ("boost", boost),
    ("surface", surface),
    ("warning", warning),
    ("error", errorC),
    ("success", success),
    ("accent", accent),
  ]

  let darkShades = ["primary-background", "secondary-background"]

  for (cName, baseColor) in colorPairs:
    let isDarkShade = dark and cName in darkShades
    let spread = luminositySpread
    for (shadeName, lumDelta) in luminosityRange(spread):
      let key = cName & shadeName
      if baseColor.kind == cckAnsi:
        result[key] = baseColor.toHex
      elif isDarkShade:
        let darkBackground = background.blend(baseColor, 0.15, 1.0)
        if key notin sys.variables:
          let shadeColor = darkBackground.blend(
            whiteColor(), spread + lumDelta, 1.0).clamped
          result[key] = shadeColor.toHex
        else:
          result[key] = sys.variables[key]
      else:
        result[key] = sys.getOrDefault(key, baseColor.lighten(lumDelta).toHex)

  if foreground.kind != cckAnsi:
    result["text"] = sys.getOrDefault("text", "auto 87%")
    result["text-muted"] = sys.getOrDefault("text-muted", "auto 60%")
    result["text-disabled"] = sys.getOrDefault("text-disabled", "auto 38%")
  else:
    result["text"] = "ansi_default"
    result["text-muted"] = "ansi_default"
    result["text-disabled"] = "ansi_default"

  result["primary-muted"] = sys.getOrDefault(
    "primary-muted", primary.blend(background, 0.7).toHex)
  result["secondary-muted"] = sys.getOrDefault(
    "secondary-muted", secondary.blend(background, 0.7).toHex)
  result["accent-muted"] = sys.getOrDefault(
    "accent-muted", accent.blend(background, 0.7).toHex)
  result["warning-muted"] = sys.getOrDefault(
    "warning-muted", warning.blend(background, 0.7).toHex)
  result["error-muted"] = sys.getOrDefault(
    "error-muted", errorC.blend(background, 0.7).toHex)
  result["success-muted"] = sys.getOrDefault(
    "success-muted", success.blend(background, 0.7).toHex)

  result["foreground-muted"] = sys.getOrDefault(
    "foreground-muted", foreground.withAlpha(0.6).toHex)
  result["foreground-disabled"] = sys.getOrDefault(
    "foreground-disabled", foreground.withAlpha(0.38).toHex)

  result["block-cursor-foreground"] = sys.getOrDefault(
    "block-cursor-foreground", result["text"])
  result["block-cursor-background"] = sys.getOrDefault(
    "block-cursor-background", primary.toHex)
  result["block-cursor-text-style"] = sys.getOrDefault(
    "block-cursor-text-style", "bold")
  result["block-cursor-blurred-foreground"] = sys.getOrDefault(
    "block-cursor-blurred-foreground", foreground.toHex)
  result["block-cursor-blurred-background"] = sys.getOrDefault(
    "block-cursor-blurred-background", primary.withAlpha(0.3).toHex)
  result["block-cursor-blurred-text-style"] = sys.getOrDefault(
    "block-cursor-blurred-text-style", "none")
  result["block-hover-background"] = sys.getOrDefault(
    "block-hover-background", boost.withAlpha(0.1).toHex)

  result["border"] = sys.getOrDefault("border", primary.toHex)
  result["border-blurred"] = sys.getOrDefault(
    "border-blurred", surface.darken(0.025).toHex)

  result["surface-active"] = sys.getOrDefault(
    "surface-active",
    surface.lighten(sys.luminositySpread / 2.5).toHex)

  let bgDk1 = parseColor(result["background-darken-1"])
  result["scrollbar"] = sys.getOrDefault(
    "scrollbar",
    (bgDk1 + primary.withAlpha(0.4)).toHex)
  result["scrollbar-hover"] = sys.getOrDefault(
    "scrollbar-hover",
    (bgDk1 + primary.withAlpha(0.5)).toHex)
  result["scrollbar-active"] = sys.getOrDefault(
    "scrollbar-active", primary.toHex)
  result["scrollbar-background"] = sys.getOrDefault(
    "scrollbar-background", result["background-darken-1"])
  result["scrollbar-corner-color"] = sys.getOrDefault(
    "scrollbar-corner-color", result["scrollbar-background"])
  result["scrollbar-background-hover"] = sys.getOrDefault(
    "scrollbar-background-hover", result["scrollbar-background"])
  result["scrollbar-background-active"] = sys.getOrDefault(
    "scrollbar-background-active", result["scrollbar-background"])

  result["link-background"] = sys.getOrDefault("link-background", "initial")
  result["link-background-hover"] = sys.getOrDefault(
    "link-background-hover", primary.toHex)
  result["link-color"] = sys.getOrDefault("link-color", result["text"])
  result["link-style"] = sys.getOrDefault("link-style", "underline")
  result["link-color-hover"] = sys.getOrDefault(
    "link-color-hover", result["text"])
  result["link-style-hover"] = sys.getOrDefault(
    "link-style-hover", "bold not underline")

  result["footer-foreground"] = sys.getOrDefault(
    "footer-foreground", foreground.toHex)
  result["footer-background"] = sys.getOrDefault(
    "footer-background", panel.toHex)
  result["footer-key-foreground"] = sys.getOrDefault(
    "footer-key-foreground", accent.toHex)
  result["footer-key-background"] = sys.getOrDefault(
    "footer-key-background", "transparent")
  result["footer-description-foreground"] = sys.getOrDefault(
    "footer-description-foreground", foreground.toHex)
  result["footer-description-background"] = sys.getOrDefault(
    "footer-description-background", "transparent")
  result["footer-item-background"] = sys.getOrDefault(
    "footer-item-background", "transparent")

  result["input-cursor-background"] = sys.getOrDefault(
    "input-cursor-background", foreground.toHex)
  result["input-cursor-foreground"] = sys.getOrDefault(
    "input-cursor-foreground", background.toHex)
  result["input-cursor-text-style"] = sys.getOrDefault(
    "input-cursor-text-style", "none")
  result["input-selection-background"] = sys.getOrDefault(
    "input-selection-background",
    parseColor(result["primary-lighten-1"]).withAlpha(0.4).toHex)
  result["input-selection-foreground"] = sys.getOrDefault(
    "input-selection-foreground", foreground.toHex)

  result["markdown-h1-color"] = sys.getOrDefault(
    "markdown-h1-color", primary.toHex)
  result["markdown-h1-background"] = sys.getOrDefault(
    "markdown-h1-background", "transparent")
  result["markdown-h1-text-style"] = sys.getOrDefault(
    "markdown-h1-text-style", "bold")

  result["markdown-h2-color"] = sys.getOrDefault(
    "markdown-h2-color", primary.toHex)
  result["markdown-h2-background"] = sys.getOrDefault(
    "markdown-h2-background", "transparent")
  result["markdown-h2-text-style"] = sys.getOrDefault(
    "markdown-h2-text-style", "underline")

  result["markdown-h3-color"] = sys.getOrDefault(
    "markdown-h3-color", primary.toHex)
  result["markdown-h3-background"] = sys.getOrDefault(
    "markdown-h3-background", "transparent")
  result["markdown-h3-text-style"] = sys.getOrDefault(
    "markdown-h3-text-style", "bold")

  result["markdown-h4-color"] = sys.getOrDefault(
    "markdown-h4-color", foreground.toHex)
  result["markdown-h4-background"] = sys.getOrDefault(
    "markdown-h4-background", "transparent")
  result["markdown-h4-text-style"] = sys.getOrDefault(
    "markdown-h4-text-style", "bold underline")

  result["markdown-h5-color"] = sys.getOrDefault(
    "markdown-h5-color", foreground.toHex)
  result["markdown-h5-background"] = sys.getOrDefault(
    "markdown-h5-background", "transparent")
  result["markdown-h5-text-style"] = sys.getOrDefault(
    "markdown-h5-text-style", "bold")

  result["markdown-h6-color"] = sys.getOrDefault(
    "markdown-h6-color", result["foreground-muted"])
  result["markdown-h6-background"] = sys.getOrDefault(
    "markdown-h6-background", "transparent")
  result["markdown-h6-text-style"] = sys.getOrDefault(
    "markdown-h6-text-style", "bold")

  result["button-foreground"] = sys.getOrDefault(
    "button-foreground", foreground.toHex)
  result["button-color-foreground"] = sys.getOrDefault(
    "button-color-foreground", result["text"])
  result["button-focus-text-style"] = sys.getOrDefault(
    "button-focus-text-style", "b reverse")

  result["ansi-background"] = "transparent"
  result["ansi-foreground"] = "transparent"

  result["screen-selection-background"] = sys.getOrDefault(
    "screen-selection-background", primary.withAlpha(0.5).toHex)
  result["screen-selection-foreground"] = sys.getOrDefault(
    "screen-selection-foreground", "transparent")
