## isonim_tui/theme/color.nim
##
## Port of `textual/color.py` (856 LOC).
##
## A `Color` is a four-component value (r, g, b, a) plus optional ANSI
## index and `auto` flag. Colors parse from hex (`#rgb`, `#rgba`,
## `#rrggbb`, `#rrggbbaa`), `rgb()` / `rgba()`, `hsl()` / `hsla()`,
## CSS named colours, and `ansi_*` names.
##
## Blending is done in linear-RGB space (gamma-corrected) when needed
## via the `darken` / `lighten` helpers that round-trip through CIE-Lab,
## matching Textual's `Color.darken` / `Color.lighten`. The plain
## `blend(other, factor)` is a *linear-RGB* lerp on the 0-255 byte
## channels — that is what Textual does for its blend operation, and we
## stay byte-for-byte compatible.
##
## Charter: this module exposes a value-typed `Color` (it is a plain
## `object`, not a `ref object`). It depends only on the cell-level
## colour kind enum from `../cells.nim` so the cascade can lower a
## theme colour to a render-time `cells.Color`.

import std/[math, strutils, parseutils, tables, hashes]
import ../cells

type
  ColorKindCss* = enum
    ## Sub-kinds of a parsed colour value. We keep ANSI as a separate
    ## state because `Color.with_alpha` / `Color.blend` short-circuit on
    ## ANSI inputs (matches Textual's behaviour).
    cckRgb       ## A normal sRGB colour with optional alpha
    cckAnsi      ## ANSI colour by index (-1 means `ansi_default`)

  Color* = object
    ## Value-typed colour. Mirrors Textual's `Color(NamedTuple)` shape:
    ## `r`, `g`, `b`, `a`, optional `ansi`, and the `auto` flag.
    kind*: ColorKindCss
    r*: uint8
    g*: uint8
    b*: uint8
    a*: float64       ## 0.0..1.0 alpha
    ansi*: int8       ## -2 = none, -1 = ansi_default, 0..15 = ANSI index
    auto*: bool       ## `auto` colour (white-or-black for contrast)

  Hsl* = object
    h*: float64  ## 0..1
    s*: float64
    l*: float64

  Hsv* = object
    h*: float64
    s*: float64
    v*: float64

  Lab* = object
    ## CIE-L*ab colour. Used internally by `darken` / `lighten`.
    l*: float64    ## 0..100
    a*: float64    ## -128..127
    b*: float64    ## -128..127

  ColorParseError* = object of CatchableError

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

proc rgb*(r, g, b: uint8; a: float64 = 1.0): Color {.inline.} =
  Color(kind: cckRgb, r: r, g: g, b: b, a: a, ansi: -2'i8, auto: false)

proc rgba*(r, g, b: uint8; a: float64): Color {.inline.} =
  rgb(r, g, b, a)

proc transparent*(): Color {.inline.} =
  rgb(0u8, 0u8, 0u8, 0.0)

proc whiteColor*(): Color {.inline.} = rgb(255u8, 255u8, 255u8, 1.0)
proc blackColor*(): Color {.inline.} = rgb(0u8, 0u8, 0u8, 1.0)

proc ansiDefault*(): Color {.inline.} =
  Color(kind: cckAnsi, r: 0, g: 0, b: 0, a: 1.0, ansi: -1'i8, auto: false)

proc ansiByIndex*(idx: int; r, g, b: uint8): Color {.inline.} =
  Color(kind: cckAnsi, r: r, g: g, b: b, a: 1.0, ansi: idx.int8, auto: false)

proc automatic*(alphaPercent: float64 = 100.0): Color {.inline.} =
  Color(kind: cckRgb, r: 0, g: 0, b: 0, a: alphaPercent / 100.0,
        ansi: -2'i8, auto: true)

proc isTransparent*(c: Color): bool {.inline.} =
  c.kind == cckRgb and c.a == 0.0

# ---------------------------------------------------------------------------
# Equality / hashing
# ---------------------------------------------------------------------------

proc `==`*(a, b: Color): bool {.inline.} =
  a.kind == b.kind and a.r == b.r and a.g == b.g and a.b == b.b and
    a.a == b.a and a.ansi == b.ansi and a.auto == b.auto

proc hash*(c: Color): Hash {.inline.} =
  result = hash(ord(c.kind))
  result = result !& hash(c.r.int) !& hash(c.g.int) !& hash(c.b.int)
  result = result !& hash(c.a) !& hash(c.ansi.int) !& hash(c.auto)
  result = !$result

# ---------------------------------------------------------------------------
# Clamping helpers
# ---------------------------------------------------------------------------

proc clamp01*(v: float64): float64 {.inline.} =
  if v < 0.0: 0.0
  elif v > 1.0: 1.0
  else: v

proc clampByte*(v: int): uint8 {.inline.} =
  if v < 0: 0u8
  elif v > 255: 255u8
  else: v.uint8

proc clampByteF*(v: float64): uint8 {.inline.} =
  ## Match Textual's behaviour: cast-to-int (truncates toward zero).
  if v < 0.0: 0u8
  elif v > 255.0: 255u8
  else: v.int.clampByte

proc clamped*(c: Color): Color =
  result = c
  result.a = clamp01(c.a)

# ---------------------------------------------------------------------------
# RGB <-> HSL
# ---------------------------------------------------------------------------

proc rgbToHls(r, g, b: float64): (float64, float64, float64) =
  ## Same algorithm as Python's `colorsys.rgb_to_hls`.
  let mx = max(max(r, g), b)
  let mn = min(min(r, g), b)
  let l = (mx + mn) / 2.0
  if mx == mn:
    return (0.0, l, 0.0)
  let d = mx - mn
  let s =
    if l > 0.5: d / (2.0 - mx - mn)
    else: d / (mx + mn)
  var h: float64
  let rc = (mx - r) / d
  let gc = (mx - g) / d
  let bc = (mx - b) / d
  if r == mx:
    h = bc - gc
  elif g == mx:
    h = 2.0 + rc - bc
  else:
    h = 4.0 + gc - rc
  h = (h / 6.0) mod 1.0
  if h < 0.0: h += 1.0
  (h, l, s)

proc hlsToRgb(h, l, s: float64): (float64, float64, float64) =
  ## Match Python's `colorsys.hls_to_rgb`.
  if s == 0.0:
    return (l, l, l)
  let m2 =
    if l <= 0.5: l * (1.0 + s)
    else: l + s - l * s
  let m1 = 2.0 * l - m2

  proc helper(h: float64): float64 =
    var hh = h
    if hh < 0.0: hh += 1.0
    if hh > 1.0: hh -= 1.0
    if hh < 1.0 / 6.0: return m1 + (m2 - m1) * 6.0 * hh
    if hh < 0.5: return m2
    if hh < 2.0 / 3.0: return m1 + (m2 - m1) * (2.0 / 3.0 - hh) * 6.0
    return m1

  (helper(h + 1.0 / 3.0), helper(h), helper(h - 1.0 / 3.0))

proc hsl*(c: Color): Hsl =
  let r = c.r.float64 / 255.0
  let g = c.g.float64 / 255.0
  let b = c.b.float64 / 255.0
  let (h, l, s) = rgbToHls(r, g, b)
  Hsl(h: h, s: s, l: l)

proc fromHsl*(h, s, l: float64): Color =
  let (r, g, b) = hlsToRgb(h, l, s)
  rgb((r * 255.0 + 0.5).int.clampByte,
      (g * 255.0 + 0.5).int.clampByte,
      (b * 255.0 + 0.5).int.clampByte)

# ---------------------------------------------------------------------------
# RGB <-> HSV
# ---------------------------------------------------------------------------

proc rgbToHsv(r, g, b: float64): (float64, float64, float64) =
  let mx = max(max(r, g), b)
  let mn = min(min(r, g), b)
  let v = mx
  if mx == mn:
    return (0.0, 0.0, v)
  let d = mx - mn
  let s = d / mx
  let rc = (mx - r) / d
  let gc = (mx - g) / d
  let bc = (mx - b) / d
  var h: float64
  if r == mx:
    h = bc - gc
  elif g == mx:
    h = 2.0 + rc - bc
  else:
    h = 4.0 + gc - rc
  h = (h / 6.0) mod 1.0
  if h < 0.0: h += 1.0
  (h, s, v)

proc hsv*(c: Color): Hsv =
  let r = c.r.float64 / 255.0
  let g = c.g.float64 / 255.0
  let b = c.b.float64 / 255.0
  let (h, s, v) = rgbToHsv(r, g, b)
  Hsv(h: h, s: s, v: v)

# ---------------------------------------------------------------------------
# RGB <-> CIE-Lab (used by darken/lighten, gamma-correct)
# ---------------------------------------------------------------------------

proc rgbToLab*(c: Color): Lab =
  ## Mirror of `textual.color.rgb_to_lab`. sRGB → linear → XYZ → Lab.
  var r = c.r.float64 / 255.0
  var g = c.g.float64 / 255.0
  var b = c.b.float64 / 255.0

  r = if r > 0.04045: pow((r + 0.055) / 1.055, 2.4) else: r / 12.92
  g = if g > 0.04045: pow((g + 0.055) / 1.055, 2.4) else: g / 12.92
  b = if b > 0.04045: pow((b + 0.055) / 1.055, 2.4) else: b / 12.92

  var x = (r * 41.24 + g * 35.76 + b * 18.05) / 95.047
  var y = (r * 21.26 + g * 71.52 + b * 7.22) / 100.0
  var z = (r * 1.93  + g * 11.92 + b * 95.05) / 108.883

  let off = 16.0 / 116.0
  x = if x > 0.008856: pow(x, 1.0 / 3.0) else: 7.787 * x + off
  y = if y > 0.008856: pow(y, 1.0 / 3.0) else: 7.787 * y + off
  z = if z > 0.008856: pow(z, 1.0 / 3.0) else: 7.787 * z + off

  Lab(l: 116.0 * y - 16.0, a: 500.0 * (x - y), b: 200.0 * (y - z))

proc labToRgb*(lab: Lab; alpha: float64 = 1.0): Color =
  ## Mirror of `textual.color.lab_to_rgb`.
  var y = (lab.l + 16.0) / 116.0
  var x = lab.a / 500.0 + y
  var z = y - lab.b / 200.0

  let off = 16.0 / 116.0
  y = if y > 0.2068930344: pow(y, 3.0) else: (y - off) / 7.787
  x = if x > 0.2068930344: 0.95047 * pow(x, 3.0) else: 0.122059 * (x - off)
  z = if z > 0.2068930344: 1.08883 * pow(z, 3.0) else: 0.139827 * (z - off)

  var r = x * 3.2406 + y * -1.5372 + z * -0.4986
  var g = x * -0.9689 + y * 1.8758 + z * 0.0415
  var b = x * 0.0557 + y * -0.2040 + z * 1.0570

  r = if r > 0.0031308: 1.055 * pow(r, 1.0 / 2.4) - 0.055 else: 12.92 * r
  g = if g > 0.0031308: 1.055 * pow(g, 1.0 / 2.4) - 0.055 else: 12.92 * g
  b = if b > 0.0031308: 1.055 * pow(b, 1.0 / 2.4) - 0.055 else: 12.92 * b

  Color(kind: cckRgb,
        r: (r * 255.0).int.clampByte,
        g: (g * 255.0).int.clampByte,
        b: (b * 255.0).int.clampByte,
        a: alpha, ansi: -2'i8, auto: false)

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

proc inverse*(c: Color): Color {.inline.} =
  Color(kind: c.kind,
        r: 255u8 - c.r, g: 255u8 - c.g, b: 255u8 - c.b,
        a: c.a, ansi: c.ansi, auto: c.auto)

proc brightness*(c: Color): float64 {.inline.} =
  ## Human perceptual brightness. Pure white = 1, pure black = 0.
  let r = c.r.float64 / 255.0
  let g = c.g.float64 / 255.0
  let b = c.b.float64 / 255.0
  (299.0 * r + 587.0 * g + 114.0 * b) / 1000.0

proc withAlpha*(c: Color; alpha: float64): Color {.inline.} =
  Color(kind: c.kind, r: c.r, g: c.g, b: c.b,
        a: alpha, ansi: c.ansi, auto: c.auto)

proc multiplyAlpha*(c: Color; alpha: float64): Color {.inline.} =
  if c.kind == cckAnsi: return c
  Color(kind: c.kind, r: c.r, g: c.g, b: c.b,
        a: c.a * alpha, ansi: c.ansi, auto: c.auto)

proc getContrastText*(c: Color; alpha: float64 = 0.95): Color =
  ## Pick white or black for max contrast against `c`. Mirrors Textual.
  if c.brightness < 0.5: whiteColor().withAlpha(alpha)
  else: blackColor().withAlpha(alpha)

proc blend*(self, destination: Color; factor: float64;
            alpha: float64 = NaN): Color =
  ## Textual `Color.blend`. ANSI destinations short-circuit. Linear-RGB
  ## lerp on byte channels (intentional: this is what Textual does, and
  ## it produces byte-identical output).
  ##
  ## For *gamma-corrected* mixing use `darken` / `lighten`, which round-
  ## trip through Lab.
  var dst = destination
  if dst.auto:
    dst = self.getContrastText(dst.a)
  if dst.kind == cckAnsi:
    return dst
  if factor <= 0.0: return self
  if factor >= 1.0: return dst

  let r1 = self.r.float64
  let g1 = self.g.float64
  let b1 = self.b.float64
  let a1 = self.a
  let r2 = dst.r.float64
  let g2 = dst.g.float64
  let b2 = dst.b.float64
  let a2 = dst.a

  let newAlpha =
    if classify(alpha) == fcNan: a1 + (a2 - a1) * factor
    else: alpha

  Color(kind: cckRgb,
        r: (r1 + (r2 - r1) * factor).int.clampByte,
        g: (g1 + (g2 - g1) * factor).int.clampByte,
        b: (b1 + (b2 - b1) * factor).int.clampByte,
        a: newAlpha, ansi: -2'i8, auto: false)

proc tint*(self, color: Color): Color =
  ## Combine alpha + colour. ANSI inputs pass through. Mirrors Textual.
  if self.kind == cckAnsi: return self
  if color.kind == cckAnsi: return self
  let r1 = self.r.float64
  let g1 = self.g.float64
  let b1 = self.b.float64
  let r2 = color.r.float64
  let g2 = color.g.float64
  let b2 = color.b.float64
  let a2 = color.a
  Color(kind: cckRgb,
        r: (r1 + (r2 - r1) * a2).int.clampByte,
        g: (g1 + (g2 - g1) * a2).int.clampByte,
        b: (b1 + (b2 - b1) * a2).int.clampByte,
        a: self.a, ansi: -2'i8, auto: false)

proc `+`*(self, other: Color): Color =
  ## `Color + Color` is `self.blend(other, other.a, alpha=1.0)`.
  blend(self, other, other.a, 1.0)

proc darken*(c: Color; amount: float64; alpha: float64 = NaN): Color =
  ## Darken by `amount` on the L axis of CIE-Lab, then convert back.
  ## Gamma-correct.
  let lab = rgbToLab(c)
  let nl = lab.l - amount * 100.0
  let na = if classify(alpha) == fcNan: c.a else: alpha
  labToRgb(Lab(l: nl, a: lab.a, b: lab.b), na).clamped

proc lighten*(c: Color; amount: float64; alpha: float64 = NaN): Color {.inline.} =
  darken(c, -amount, alpha)

proc monochrome*(c: Color): Color {.inline.} =
  let gray = round(c.r.float64 * 0.2126 + c.g.float64 * 0.7152 +
                   c.b.float64 * 0.0722).int.clampByte
  Color(kind: cckRgb, r: gray, g: gray, b: gray,
        a: c.a, ansi: -2'i8, auto: false)

# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

proc toHex*(c: Color): string =
  ## CSS `#RRGGBB` or `#RRGGBBAA`. Matches Textual's `Color.hex`.
  let cl = c.clamped
  if cl.kind == cckAnsi:
    if cl.ansi == -1: return "ansi_default"
    return "ansi_" & $cl.ansi  # unused fall-through
  if cl.a == 1.0:
    result = "#"
    result.add(toHex(cl.r.int, 2).toUpperAscii)
    result.add(toHex(cl.g.int, 2).toUpperAscii)
    result.add(toHex(cl.b.int, 2).toUpperAscii)
  else:
    result = "#"
    result.add(toHex(cl.r.int, 2).toUpperAscii)
    result.add(toHex(cl.g.int, 2).toUpperAscii)
    result.add(toHex(cl.b.int, 2).toUpperAscii)
    result.add(toHex((cl.a * 255.0).int, 2).toUpperAscii)

proc toHex6*(c: Color): string =
  ## `#RRGGBB` (alpha discarded).
  let cl = c.clamped
  result = "#"
  result.add(toHex(cl.r.int, 2).toUpperAscii)
  result.add(toHex(cl.g.int, 2).toUpperAscii)
  result.add(toHex(cl.b.int, 2).toUpperAscii)

proc toCssString*(c: Color): string =
  ## CSS `rgb(...)` / `rgba(...)` / `auto` / `ansi_*`. Matches Textual.
  if c.auto:
    let alphaPct = clamp01(c.a) * 100.0
    if alphaPct == 100.0: return "auto"
    if alphaPct == alphaPct.int.float64: return "auto " & $alphaPct.int & "%"
    return "auto " & formatFloat(alphaPct, ffDecimal, 1) & "%"
  if c.kind == cckAnsi:
    if c.ansi == -1: return "ansi_default"
    # Caller can resolve a pretty name via ANSI_NAMES.
    return "ansi_" & $c.ansi
  if c.a == 1.0:
    return "rgb(" & $c.r & "," & $c.g & "," & $c.b & ")"
  return "rgba(" & $c.r & "," & $c.g & "," & $c.b & "," &
         formatFloat(c.a, ffDefault, 0) & ")"

# ---------------------------------------------------------------------------
# ANSI palette + named-colour table
# ---------------------------------------------------------------------------

const AnsiNames* = [
  "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
  "bright_black", "bright_red", "bright_green", "bright_yellow",
  "bright_blue", "bright_magenta", "bright_cyan", "bright_white"
]

# Web colour keywords from CSS Color Module Level 4 — same set as
# `textual/_color_constants.py`.
const NamedColours* = {
  "transparent":            (0u8, 0u8, 0u8, 0u8),
  "ansi_black":             (0u8, 0u8, 0u8, 255u8),
  "ansi_red":               (128u8, 0u8, 0u8, 255u8),
  "ansi_green":             (0u8, 128u8, 0u8, 255u8),
  "ansi_yellow":            (128u8, 128u8, 0u8, 255u8),
  "ansi_blue":              (0u8, 0u8, 128u8, 255u8),
  "ansi_magenta":           (128u8, 0u8, 128u8, 255u8),
  "ansi_cyan":              (0u8, 128u8, 128u8, 255u8),
  "ansi_white":             (192u8, 192u8, 192u8, 255u8),
  "ansi_bright_black":      (128u8, 128u8, 128u8, 255u8),
  "ansi_bright_red":        (255u8, 0u8, 0u8, 255u8),
  "ansi_bright_green":      (0u8, 255u8, 0u8, 255u8),
  "ansi_bright_yellow":     (255u8, 255u8, 0u8, 255u8),
  "ansi_bright_blue":       (0u8, 0u8, 255u8, 255u8),
  "ansi_bright_magenta":    (255u8, 0u8, 255u8, 255u8),
  "ansi_bright_cyan":       (0u8, 255u8, 255u8, 255u8),
  "ansi_bright_white":      (255u8, 255u8, 255u8, 255u8),
  "black":                  (0u8, 0u8, 0u8, 255u8),
  "silver":                 (192u8, 192u8, 192u8, 255u8),
  "gray":                   (128u8, 128u8, 128u8, 255u8),
  "white":                  (255u8, 255u8, 255u8, 255u8),
  "maroon":                 (128u8, 0u8, 0u8, 255u8),
  "red":                    (255u8, 0u8, 0u8, 255u8),
  "purple":                 (128u8, 0u8, 128u8, 255u8),
  "fuchsia":                (255u8, 0u8, 255u8, 255u8),
  "green":                  (0u8, 128u8, 0u8, 255u8),
  "lime":                   (0u8, 255u8, 0u8, 255u8),
  "olive":                  (128u8, 128u8, 0u8, 255u8),
  "yellow":                 (255u8, 255u8, 0u8, 255u8),
  "navy":                   (0u8, 0u8, 128u8, 255u8),
  "blue":                   (0u8, 0u8, 255u8, 255u8),
  "teal":                   (0u8, 128u8, 128u8, 255u8),
  "aqua":                   (0u8, 255u8, 255u8, 255u8),
  "orange":                 (255u8, 165u8, 0u8, 255u8),
  "aliceblue":              (240u8, 248u8, 255u8, 255u8),
  "antiquewhite":           (250u8, 235u8, 215u8, 255u8),
  "aquamarine":             (127u8, 255u8, 212u8, 255u8),
  "azure":                  (240u8, 255u8, 255u8, 255u8),
  "beige":                  (245u8, 245u8, 220u8, 255u8),
  "bisque":                 (255u8, 228u8, 196u8, 255u8),
  "blanchedalmond":         (255u8, 235u8, 205u8, 255u8),
  "blueviolet":             (138u8, 43u8, 226u8, 255u8),
  "brown":                  (165u8, 42u8, 42u8, 255u8),
  "burlywood":              (222u8, 184u8, 135u8, 255u8),
  "cadetblue":              (95u8, 158u8, 160u8, 255u8),
  "chartreuse":             (127u8, 255u8, 0u8, 255u8),
  "chocolate":              (210u8, 105u8, 30u8, 255u8),
  "coral":                  (255u8, 127u8, 80u8, 255u8),
  "cornflowerblue":         (100u8, 149u8, 237u8, 255u8),
  "cornsilk":               (255u8, 248u8, 220u8, 255u8),
  "crimson":                (220u8, 20u8, 60u8, 255u8),
  "cyan":                   (0u8, 255u8, 255u8, 255u8),
  "darkblue":               (0u8, 0u8, 139u8, 255u8),
  "darkcyan":               (0u8, 139u8, 139u8, 255u8),
  "darkgoldenrod":          (184u8, 134u8, 11u8, 255u8),
  "darkgray":               (169u8, 169u8, 169u8, 255u8),
  "darkgreen":              (0u8, 100u8, 0u8, 255u8),
  "darkgrey":               (169u8, 169u8, 169u8, 255u8),
  "darkkhaki":              (189u8, 183u8, 107u8, 255u8),
  "darkmagenta":            (139u8, 0u8, 139u8, 255u8),
  "darkolivegreen":         (85u8, 107u8, 47u8, 255u8),
  "darkorange":             (255u8, 140u8, 0u8, 255u8),
  "darkorchid":             (153u8, 50u8, 204u8, 255u8),
  "darkred":                (139u8, 0u8, 0u8, 255u8),
  "darksalmon":             (233u8, 150u8, 122u8, 255u8),
  "darkseagreen":           (143u8, 188u8, 143u8, 255u8),
  "darkslateblue":          (72u8, 61u8, 139u8, 255u8),
  "darkslategray":          (47u8, 79u8, 79u8, 255u8),
  "darkslategrey":          (47u8, 79u8, 79u8, 255u8),
  "darkturquoise":          (0u8, 206u8, 209u8, 255u8),
  "darkviolet":             (148u8, 0u8, 211u8, 255u8),
  "deeppink":               (255u8, 20u8, 147u8, 255u8),
  "deepskyblue":            (0u8, 191u8, 255u8, 255u8),
  "dimgray":                (105u8, 105u8, 105u8, 255u8),
  "dimgrey":                (105u8, 105u8, 105u8, 255u8),
  "dodgerblue":             (30u8, 144u8, 255u8, 255u8),
  "firebrick":              (178u8, 34u8, 34u8, 255u8),
  "floralwhite":            (255u8, 250u8, 240u8, 255u8),
  "forestgreen":            (34u8, 139u8, 34u8, 255u8),
  "gainsboro":              (220u8, 220u8, 220u8, 255u8),
  "ghostwhite":             (248u8, 248u8, 255u8, 255u8),
  "gold":                   (255u8, 215u8, 0u8, 255u8),
  "goldenrod":              (218u8, 165u8, 32u8, 255u8),
  "greenyellow":            (173u8, 255u8, 47u8, 255u8),
  "grey":                   (128u8, 128u8, 128u8, 255u8),
  "honeydew":               (240u8, 255u8, 240u8, 255u8),
  "hotpink":                (255u8, 105u8, 180u8, 255u8),
  "indianred":              (205u8, 92u8, 92u8, 255u8),
  "indigo":                 (75u8, 0u8, 130u8, 255u8),
  "ivory":                  (255u8, 255u8, 240u8, 255u8),
  "khaki":                  (240u8, 230u8, 140u8, 255u8),
  "lavender":               (230u8, 230u8, 250u8, 255u8),
  "lavenderblush":          (255u8, 240u8, 245u8, 255u8),
  "lawngreen":              (124u8, 252u8, 0u8, 255u8),
  "lemonchiffon":           (255u8, 250u8, 205u8, 255u8),
  "lightblue":              (173u8, 216u8, 230u8, 255u8),
  "lightcoral":             (240u8, 128u8, 128u8, 255u8),
  "lightcyan":              (224u8, 255u8, 255u8, 255u8),
  "lightgoldenrodyellow":   (250u8, 250u8, 210u8, 255u8),
  "lightgray":              (211u8, 211u8, 211u8, 255u8),
  "lightgreen":             (144u8, 238u8, 144u8, 255u8),
  "lightgrey":              (211u8, 211u8, 211u8, 255u8),
  "lightpink":              (255u8, 182u8, 193u8, 255u8),
  "lightsalmon":            (255u8, 160u8, 122u8, 255u8),
  "lightseagreen":          (32u8, 178u8, 170u8, 255u8),
  "lightskyblue":           (135u8, 206u8, 250u8, 255u8),
  "lightslategray":         (119u8, 136u8, 153u8, 255u8),
  "lightslategrey":         (119u8, 136u8, 153u8, 255u8),
  "lightsteelblue":         (176u8, 196u8, 222u8, 255u8),
  "lightyellow":            (255u8, 255u8, 224u8, 255u8),
  "limegreen":              (50u8, 205u8, 50u8, 255u8),
  "linen":                  (250u8, 240u8, 230u8, 255u8),
  "magenta":                (255u8, 0u8, 255u8, 255u8),
  "mediumaquamarine":       (102u8, 205u8, 170u8, 255u8),
  "mediumblue":             (0u8, 0u8, 205u8, 255u8),
  "mediumorchid":           (186u8, 85u8, 211u8, 255u8),
  "mediumpurple":           (147u8, 112u8, 219u8, 255u8),
  "mediumseagreen":         (60u8, 179u8, 113u8, 255u8),
  "mediumslateblue":        (123u8, 104u8, 238u8, 255u8),
  "mediumspringgreen":      (0u8, 250u8, 154u8, 255u8),
  "mediumturquoise":        (72u8, 209u8, 204u8, 255u8),
  "mediumvioletred":        (199u8, 21u8, 133u8, 255u8),
  "midnightblue":           (25u8, 25u8, 112u8, 255u8),
  "mintcream":              (245u8, 255u8, 250u8, 255u8),
  "mistyrose":              (255u8, 228u8, 225u8, 255u8),
  "moccasin":               (255u8, 228u8, 181u8, 255u8),
  "navajowhite":            (255u8, 222u8, 173u8, 255u8),
  "oldlace":                (253u8, 245u8, 230u8, 255u8),
  "olivedrab":              (107u8, 142u8, 35u8, 255u8),
  "orangered":              (255u8, 69u8, 0u8, 255u8),
  "orchid":                 (218u8, 112u8, 214u8, 255u8),
  "palegoldenrod":          (238u8, 232u8, 170u8, 255u8),
  "palegreen":              (152u8, 251u8, 152u8, 255u8),
  "paleturquoise":          (175u8, 238u8, 238u8, 255u8),
  "palevioletred":          (219u8, 112u8, 147u8, 255u8),
  "papayawhip":             (255u8, 239u8, 213u8, 255u8),
  "peachpuff":              (255u8, 218u8, 185u8, 255u8),
  "peru":                   (205u8, 133u8, 63u8, 255u8),
  "pink":                   (255u8, 192u8, 203u8, 255u8),
  "plum":                   (221u8, 160u8, 221u8, 255u8),
  "powderblue":             (176u8, 224u8, 230u8, 255u8),
  "rosybrown":              (188u8, 143u8, 143u8, 255u8),
  "royalblue":              (65u8, 105u8, 225u8, 255u8),
  "saddlebrown":            (139u8, 69u8, 19u8, 255u8),
  "salmon":                 (250u8, 128u8, 114u8, 255u8),
  "sandybrown":             (244u8, 164u8, 96u8, 255u8),
  "seagreen":               (46u8, 139u8, 87u8, 255u8),
  "seashell":               (255u8, 245u8, 238u8, 255u8),
  "sienna":                 (160u8, 82u8, 45u8, 255u8),
  "skyblue":                (135u8, 206u8, 235u8, 255u8),
  "slateblue":              (106u8, 90u8, 205u8, 255u8),
  "slategray":              (112u8, 128u8, 144u8, 255u8),
  "slategrey":              (112u8, 128u8, 144u8, 255u8),
  "snow":                   (255u8, 250u8, 250u8, 255u8),
  "springgreen":            (0u8, 255u8, 127u8, 255u8),
  "steelblue":              (70u8, 130u8, 180u8, 255u8),
  "tan":                    (210u8, 180u8, 140u8, 255u8),
  "thistle":                (216u8, 191u8, 216u8, 255u8),
  "tomato":                 (255u8, 99u8, 71u8, 255u8),
  "turquoise":              (64u8, 224u8, 208u8, 255u8),
  "violet":                 (238u8, 130u8, 238u8, 255u8),
  "wheat":                  (245u8, 222u8, 179u8, 255u8),
  "whitesmoke":             (245u8, 245u8, 245u8, 255u8),
  "yellowgreen":            (154u8, 205u8, 50u8, 255u8),
  "rebeccapurple":          (102u8, 51u8, 153u8, 255u8),
}.toTable

proc lookupNamedColor*(name: string): (bool, uint8, uint8, uint8, uint8) =
  ## Returns `(found, r, g, b, a)`. Lookup is case-sensitive (matches
  ## Textual's `COLOR_NAME_TO_RGB.get(...)` behaviour for parser input).
  if name in NamedColours:
    let t = NamedColours[name]
    return (true, t[0], t[1], t[2], t[3])
  (false, 0u8, 0u8, 0u8, 0u8)

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

proc parseColor*(text: string): Color =
  ## Parse a CSS-style colour string. Matches `Color.parse` in
  ## `textual/color.py` for every documented input format.
  let s = text.strip()
  if s.len == 0:
    raise newException(ColorParseError, "empty color string")

  # ansi_default
  if s == "ansi_default":
    return ansiDefault()

  # ansi_<name>
  if s.startsWith("ansi_"):
    let pretty = s[5 .. ^1]
    var idx = -1
    for i, n in AnsiNames:
      if n == pretty:
        idx = i
        break
    if idx >= 0:
      let (found, r, g, b, _) = lookupNamedColor(s)
      if found:
        return ansiByIndex(idx, r, g, b)

  # Named colour
  let (named, r0, g0, b0, a0) = lookupNamedColor(s)
  if named:
    return rgb(r0, g0, b0, a0.float64 / 255.0)

  # Hex / rgb / rgba / hsl / hsla
  if s[0] == '#':
    let hex = s[1 .. ^1]
    try:
      case hex.len
      of 3:
        let r = parseHexInt(hex[0..0] & hex[0..0])
        let g = parseHexInt(hex[1..1] & hex[1..1])
        let b = parseHexInt(hex[2..2] & hex[2..2])
        return rgb(r.uint8, g.uint8, b.uint8)
      of 4:
        let r = parseHexInt(hex[0..0] & hex[0..0])
        let g = parseHexInt(hex[1..1] & hex[1..1])
        let b = parseHexInt(hex[2..2] & hex[2..2])
        let a = parseHexInt(hex[3..3] & hex[3..3])
        return rgb(r.uint8, g.uint8, b.uint8, a.float64 / 255.0)
      of 6:
        let r = parseHexInt(hex[0..1])
        let g = parseHexInt(hex[2..3])
        let b = parseHexInt(hex[4..5])
        return rgb(r.uint8, g.uint8, b.uint8)
      of 8:
        let r = parseHexInt(hex[0..1])
        let g = parseHexInt(hex[2..3])
        let b = parseHexInt(hex[4..5])
        let a = parseHexInt(hex[6..7])
        return rgb(r.uint8, g.uint8, b.uint8, a.float64 / 255.0)
      else:
        raise newException(ColorParseError, "invalid hex color: " & s)
    except ValueError as e:
      raise newException(ColorParseError, "invalid hex color: " & s & " (" & e.msg & ")")

  # rgb(...) / rgba(...) / hsl(...) / hsla(...)
  let openIdx = s.find('(')
  let closeIdx = s.rfind(')')
  if openIdx >= 0 and closeIdx > openIdx:
    let funcName = s[0 ..< openIdx].toLowerAscii
    let inner = s[openIdx + 1 ..< closeIdx]
    let parts = inner.split(',')
    case funcName
    of "rgb":
      if parts.len < 3:
        raise newException(ColorParseError, "rgb requires 3 args: " & s)
      var rf, gf, bf: float
      discard parseFloat(parts[0].strip(), rf)
      discard parseFloat(parts[1].strip(), gf)
      discard parseFloat(parts[2].strip(), bf)
      return rgb(rf.int.clampByte, gf.int.clampByte, bf.int.clampByte)
    of "rgba":
      if parts.len < 4:
        raise newException(ColorParseError, "rgba requires 4 args: " & s)
      var rf, gf, bf, af: float
      discard parseFloat(parts[0].strip(), rf)
      discard parseFloat(parts[1].strip(), gf)
      discard parseFloat(parts[2].strip(), bf)
      discard parseFloat(parts[3].strip(), af)
      return rgb(rf.int.clampByte, gf.int.clampByte, bf.int.clampByte,
                 clamp01(af))
    of "hsl":
      if parts.len < 3:
        raise newException(ColorParseError, "hsl requires 3 args: " & s)
      var hf: float
      discard parseFloat(parts[0].strip(), hf)
      let h = (hf.float64 mod 360.0) / 360.0
      let sp = parts[1].strip()
      let lp = parts[2].strip()
      var sv, lv: float
      discard parseFloat(sp.strip(chars = {'%', ' '}), sv)
      discard parseFloat(lp.strip(chars = {'%', ' '}), lv)
      return fromHsl(h, sv / 100.0, lv / 100.0)
    of "hsla":
      if parts.len < 4:
        raise newException(ColorParseError, "hsla requires 4 args: " & s)
      var hf: float
      discard parseFloat(parts[0].strip(), hf)
      let h = (hf.float64 mod 360.0) / 360.0
      let sp = parts[1].strip()
      let lp = parts[2].strip()
      var sv, lv, av: float
      discard parseFloat(sp.strip(chars = {'%', ' '}), sv)
      discard parseFloat(lp.strip(chars = {'%', ' '}), lv)
      discard parseFloat(parts[3].strip(), av)
      return fromHsl(h, sv / 100.0, lv / 100.0).withAlpha(clamp01(av))
    else:
      raise newException(ColorParseError, "unknown color function: " & funcName)

  raise newException(ColorParseError, "failed to parse color: " & s)

proc tryParseColor*(text: string): (bool, Color) =
  try:
    let c = parseColor(text)
    (true, c)
  except ColorParseError:
    (false, transparent())

# ---------------------------------------------------------------------------
# Lowering to cells.Color (render-time)
# ---------------------------------------------------------------------------

proc toCellsColor*(c: Color): cells.Color =
  ## Drop alpha + auto, fall back to a render-time `cells.Color`. The
  ## compositor combines alpha through the cell-merge step (M8).
  case c.kind
  of cckRgb:
    if c.a == 0.0: return defaultColor()
    rgbColor(c.r, c.g, c.b)
  of cckAnsi:
    if c.ansi < 0 or c.ansi > 15: return defaultColor()
    ansiColor(AnsiColor(c.ansi.int))
