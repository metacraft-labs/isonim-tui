## isonim_tui/css/properties.nim
##
## Typed property values for the M5 CSS engine.
##
## Charter: every value is a typed enum or tagged union. No string
## fall-through. `width: 100%` parses to `Scalar(unit: suPercent,
## value: 100.0)`, never `string("100%")`.
##
## Scope: the M5-closure expanded property set. The original M5 ship
## delivered the 12 load-bearing core properties (width/height/edges/
## color/border/text/display/visibility/layout/dock). The M5 closure
## drop adds typed support for: per-edge spacing (margin-top/...,
## padding-top/...), per-edge borders, overflow / overflow-x /
## overflow-y, text-align, offset / offset-x / offset-y, align /
## align-horizontal / align-vertical, opacity, layer / layers, tint,
## scrollbar-* sizing and colours, link-* colour and style,
## border-title-* and border-subtitle-* (colour, background, style,
## align). Together these are the properties referenced by the M11-M21
## widget set, the existing TCSS fixtures, and the M7 animation engine.
##
## Properties still deferred (require deeper architectural work and so
## are explicitly not part of this closure):
##   - `keyline` — needs a per-edge rendering pass.
##   - `auto-color` — depends on the M6 luminosity engine selecting
##     contrast.
##   - `text-overflow: ellipsis` — needs the wrap engine to learn the
##     ellipsis policy.
##   - `text-wrap` and `overflow: scroll` runtime — depend on a
##     scroll/clip pass that lives outside the cascade.

import std/[strutils, parseutils, tables]
import ../cells

# ----------------------------------------------------------------------------
# Scalar (length values)
# ----------------------------------------------------------------------------

type
  ScalarUnit* = enum
    ## Units understood by the property system. Mirrors Textual's
    ## `Unit` enum from `css/scalar.py`.
    suCells       ## Bare integer: number of cells
    suPercent     ## `100%`
    suFr          ## `1fr` — flex-grow ratio
    suViewW       ## `100vw` / `100w`
    suViewH       ## `100vh` / `100h`
    suAuto        ## `auto`

  Scalar* = object
    ## Length-like value. Tagged-union — never a string.
    unit*: ScalarUnit
    value*: float64

proc cellsScalar*(n: int): Scalar {.inline.} =
  Scalar(unit: suCells, value: n.float64)

proc percent*(n: float64): Scalar {.inline.} =
  Scalar(unit: suPercent, value: n)

proc frUnit*(n: float64): Scalar {.inline.} =
  Scalar(unit: suFr, value: n)

proc autoScalar*(): Scalar {.inline.} =
  Scalar(unit: suAuto, value: 0.0)

proc `==`*(a, b: Scalar): bool {.inline.} =
  a.unit == b.unit and a.value == b.value

proc `$`*(s: Scalar): string =
  case s.unit
  of suCells:    $s.value.int
  of suPercent:  $s.value & "%"
  of suFr:       $s.value & "fr"
  of suViewW:    $s.value & "vw"
  of suViewH:    $s.value & "vh"
  of suAuto:     "auto"

proc parseScalar*(text: string): Scalar =
  ## Parse a single scalar token value. Accepts pure numbers and
  ## values with the units handled by `tokenize.nim`. Raises ValueError
  ## on malformed input.
  if text.len == 0:
    raise newException(ValueError, "empty scalar")
  if text == "auto":
    return autoScalar()
  if text.endsWith("%"):
    var v: float
    discard parseFloat(text[0 ..< text.len - 1], v)
    return Scalar(unit: suPercent, value: v)
  if text.endsWith("fr"):
    var v: float
    discard parseFloat(text[0 ..< text.len - 2], v)
    return Scalar(unit: suFr, value: v)
  if text.endsWith("vw"):
    var v: float
    discard parseFloat(text[0 ..< text.len - 2], v)
    return Scalar(unit: suViewW, value: v)
  if text.endsWith("vh"):
    var v: float
    discard parseFloat(text[0 ..< text.len - 2], v)
    return Scalar(unit: suViewH, value: v)
  if text.endsWith("w") and text.len > 1 and (text[text.len - 2] in {'0'..'9', '.'}):
    var v: float
    discard parseFloat(text[0 ..< text.len - 1], v)
    return Scalar(unit: suViewW, value: v)
  if text.endsWith("h") and text.len > 1 and (text[text.len - 2] in {'0'..'9', '.'}):
    var v: float
    discard parseFloat(text[0 ..< text.len - 1], v)
    return Scalar(unit: suViewH, value: v)
  # Bare integer / float
  var v: float
  if parseFloat(text, v) == 0:
    raise newException(ValueError, "cannot parse scalar: " & text)
  return Scalar(unit: suCells, value: v)

# ----------------------------------------------------------------------------
# Edges (for margin/padding shorthand)
# ----------------------------------------------------------------------------

type
  Edges* = object
    ## Four-edge value used by margin and padding. Stored as `int` cells
    ## for terminal layout; `auto` and percentage cases keep the scalar.
    top*: Scalar
    right*: Scalar
    bottom*: Scalar
    left*: Scalar

proc edgesAll*(s: Scalar): Edges {.inline.} =
  Edges(top: s, right: s, bottom: s, left: s)

proc edgesEqual*(a, b: Edges): bool {.inline.} =
  a.top == b.top and a.right == b.right and a.bottom == b.bottom and a.left == b.left

proc parseEdges*(values: openArray[Scalar]): Edges =
  ## Apply CSS shorthand expansion: `[a]` → all-four, `[a b]` → top/bottom,
  ## left/right, `[a b c]` → top, l/r, bottom, `[a b c d]` → t,r,b,l.
  case values.len
  of 1:
    edgesAll(values[0])
  of 2:
    Edges(top: values[0], right: values[1], bottom: values[0], left: values[1])
  of 3:
    Edges(top: values[0], right: values[1], bottom: values[2], left: values[1])
  of 4:
    Edges(top: values[0], right: values[1], bottom: values[2], left: values[3])
  else:
    raise newException(ValueError, "edges shorthand requires 1-4 values")

# ----------------------------------------------------------------------------
# Color values (CSS-level, separate from cells.Color which is render-time)
# ----------------------------------------------------------------------------

type
  CssColorKind* = enum
    cckTransparent  ## `transparent`
    cckCurrent      ## `auto` / `currentcolor`
    cckRgb          ## explicit r/g/b/a
    cckNamed        ## one of the named colours
    cckAnsi         ## `ansi_red`, `ansi_blue`, …
    cckVarRef       ## `$primary` — resolved later by stylesheet

  CssColor* = object
    kind*: CssColorKind
    r*: uint8
    g*: uint8
    b*: uint8
    a*: uint8
    name*: string  ## for cckNamed / cckAnsi / cckVarRef

proc rgbCss*(r, g, b: uint8; a: uint8 = 255): CssColor {.inline.} =
  CssColor(kind: cckRgb, r: r, g: g, b: b, a: a)

proc namedCss*(name: string): CssColor {.inline.} =
  CssColor(kind: cckNamed, name: name)

proc ansiCss*(name: string): CssColor {.inline.} =
  CssColor(kind: cckAnsi, name: name)

proc varRefCss*(name: string): CssColor {.inline.} =
  CssColor(kind: cckVarRef, name: name)

proc transparentCss*(): CssColor {.inline.} =
  CssColor(kind: cckTransparent)

proc `==`*(a, b: CssColor): bool {.inline.} =
  if a.kind != b.kind: return false
  case a.kind
  of cckTransparent, cckCurrent: true
  of cckRgb: a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
  of cckNamed, cckAnsi, cckVarRef: a.name == b.name

# Named colour table (subset — extend in M6 with full Textual palette).
const namedColours = {
  "black":   (0u8,   0u8,   0u8),
  "white":   (255u8, 255u8, 255u8),
  "red":     (255u8, 0u8,   0u8),
  "green":   (0u8,   255u8, 0u8),
  "blue":    (0u8,   0u8,   255u8),
  "yellow":  (255u8, 255u8, 0u8),
  "cyan":    (0u8,   255u8, 255u8),
  "magenta": (255u8, 0u8,   255u8),
  "gray":    (128u8, 128u8, 128u8),
  "grey":    (128u8, 128u8, 128u8),
  "silver":  (192u8, 192u8, 192u8),
  "maroon":  (128u8, 0u8,   0u8),
  "olive":   (128u8, 128u8, 0u8),
  "navy":    (0u8,   0u8,   128u8),
  "purple":  (128u8, 0u8,   128u8),
  "teal":    (0u8,   128u8, 128u8),
  "aqua":    (0u8,   255u8, 255u8),
  "fuchsia": (255u8, 0u8,   255u8),
  "lime":    (0u8,   255u8, 0u8),
  "orange":  (255u8, 165u8, 0u8),
  "pink":    (255u8, 192u8, 203u8),
}.toTable

proc lookupNamed*(name: string): (bool, uint8, uint8, uint8) =
  ## Returns `(found, r, g, b)`. Used by the cascade to materialize a
  ## `CssColor(cckNamed)` into RGB at computed-style time.
  let lower = name.toLowerAscii
  if lower in namedColours:
    let t = namedColours[lower]
    return (true, t[0], t[1], t[2])
  (false, 0u8, 0u8, 0u8)

proc parseHexColor*(text: string): CssColor =
  ## Parse `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`. Caller passes the
  ## leading `#`.
  if text.len == 0 or text[0] != '#':
    raise newException(ValueError, "hex color must start with #")
  let hex = text[1 .. ^1]
  var r, g, b, a: uint8
  a = 255
  case hex.len
  of 3:
    r = parseHexInt(hex[0..0] & hex[0..0]).uint8
    g = parseHexInt(hex[1..1] & hex[1..1]).uint8
    b = parseHexInt(hex[2..2] & hex[2..2]).uint8
  of 4:
    r = parseHexInt(hex[0..0] & hex[0..0]).uint8
    g = parseHexInt(hex[1..1] & hex[1..1]).uint8
    b = parseHexInt(hex[2..2] & hex[2..2]).uint8
    a = parseHexInt(hex[3..3] & hex[3..3]).uint8
  of 6:
    r = parseHexInt(hex[0..1]).uint8
    g = parseHexInt(hex[2..3]).uint8
    b = parseHexInt(hex[4..5]).uint8
  of 8:
    r = parseHexInt(hex[0..1]).uint8
    g = parseHexInt(hex[2..3]).uint8
    b = parseHexInt(hex[4..5]).uint8
    a = parseHexInt(hex[6..7]).uint8
  else:
    raise newException(ValueError, "invalid hex color: " & text)
  rgbCss(r, g, b, a)

proc parseRgbFunc*(text: string): CssColor =
  ## Parse `rgb(R, G, B)` / `rgba(R, G, B, A)`. Text includes the function
  ## name and parens.
  let openIdx = text.find('(')
  let closeIdx = text.rfind(')')
  if openIdx < 0 or closeIdx <= openIdx:
    raise newException(ValueError, "malformed rgb function: " & text)
  let funcName = text[0 ..< openIdx]
  let inner = text[openIdx + 1 ..< closeIdx]
  let parts = inner.split(',')
  if parts.len < 3:
    raise newException(ValueError, "rgb requires 3+ args: " & text)
  proc clamp(v: int): uint8 =
    if v < 0: 0u8 elif v > 255: 255u8 else: v.uint8
  let r = clamp(parseInt(parts[0].strip()))
  let g = clamp(parseInt(parts[1].strip()))
  let b = clamp(parseInt(parts[2].strip()))
  var alpha: uint8 = 255
  if parts.len >= 4:
    var f: float
    discard parseFloat(parts[3].strip(), f)
    if f < 0: f = 0
    if f > 1.0: f = 1.0
    alpha = (f * 255.0).uint8
  if funcName == "rgba" or parts.len >= 4:
    rgbCss(r, g, b, alpha)
  else:
    rgbCss(r, g, b, 255)

proc toCellsColor*(c: CssColor): cells.Color =
  ## Materialize a CSS-level color into the cell-render Color used by
  ## the M0 cell grid. Variable refs and "current" values fall back to
  ## default until the stylesheet resolves them.
  case c.kind
  of cckRgb: rgbColor(c.r, c.g, c.b)
  of cckNamed:
    let (found, r, g, b) = lookupNamed(c.name)
    if found: rgbColor(r, g, b) else: defaultColor()
  of cckAnsi:
    # ansi_red, ansi_bright_red, etc.
    let lower = c.name.toLowerAscii
    let stripped = if lower.startsWith("ansi_"): lower[5..^1] else: lower
    case stripped
    of "black":          ansiColor(acBlack)
    of "red":            ansiColor(acRed)
    of "green":          ansiColor(acGreen)
    of "yellow":         ansiColor(acYellow)
    of "blue":           ansiColor(acBlue)
    of "magenta":        ansiColor(acMagenta)
    of "cyan":           ansiColor(acCyan)
    of "white":          ansiColor(acWhite)
    of "bright_black":   ansiColor(acBrightBlack)
    of "bright_red":     ansiColor(acBrightRed)
    of "bright_green":   ansiColor(acBrightGreen)
    of "bright_yellow":  ansiColor(acBrightYellow)
    of "bright_blue":    ansiColor(acBrightBlue)
    of "bright_magenta": ansiColor(acBrightMagenta)
    of "bright_cyan":    ansiColor(acBrightCyan)
    of "bright_white":   ansiColor(acBrightWhite)
    else: defaultColor()
  of cckTransparent, cckCurrent, cckVarRef:
    defaultColor()

# ----------------------------------------------------------------------------
# Display, visibility, layout, dock
# ----------------------------------------------------------------------------

type
  DisplayKind* = enum
    dkBlock
    dkNone

  VisibilityKind* = enum
    vkVisible
    vkHidden

  LayoutKind* = enum
    lkVertical
    lkHorizontal
    lkGrid
    lkStream

  DockKind* = enum
    dockNone
    dockTop
    dockBottom
    dockLeft
    dockRight

  BorderStyle* = enum
    bsNone
    bsAscii
    bsHidden
    bsBlank
    bsRound
    bsSolid
    bsDouble
    bsDashed
    bsHeavy
    bsInner
    bsOuter
    bsThick
    bsBlock
    bsHkey
    bsVkey
    bsTall
    bsPanel
    bsTab
    bsWide

  TextStyleFlag* = enum
    tsBold
    tsItalic
    tsUnderline
    tsStrike
    tsReverse
    tsDim
    tsBlink
    tsOverline

  OverflowKind* = enum
    ## `overflow` — what happens when content exceeds the box.
    ovVisible   ## let content paint past the box
    ovHidden    ## clip silently
    ovScroll    ## clip and reserve a scrollbar
    ovAuto      ## scrollbar appears only if content overflows

  TextAlignKind* = enum
    taLeft
    taCenter
    taRight
    taJustify
    taStart   ## flow-relative left
    taEnd     ## flow-relative right

  HAlignKind* = enum
    ## `align-horizontal` plus the horizontal half of `align`.
    haLeft
    haCenter
    haRight

  VAlignKind* = enum
    ## `align-vertical` plus the vertical half of `align`.
    vaTop
    vaMiddle
    vaBottom

  Offset* = object
    ## Two-axis offset value used by `offset` and animated by the M7
    ## animator. Stored as cell-typed Scalars so `offset: 50% 0` lands
    ## as `(suPercent, 50.0)` / `(suCells, 0)`.
    x*: Scalar
    y*: Scalar

  EdgeBorder* = object
    ## A per-edge border — style + colour. The bare `border-top`,
    ## `border-right`, etc. shorthands take a style keyword optionally
    ## followed by a colour (`border-top: solid red`). Plain colour-
    ## only or style-only forms are accepted; missing pieces fall back
    ## to the cascade's existing `border-style` / `border-color`.
    style*: BorderStyle
    styleSet*: bool
    color*: CssColor
    colorSet*: bool

  GridTrackKind* = enum
    ## Kinds of CSS-grid track sizes that the M5 grid resolver
    ## understands. Mirrors Textual's `Scalar` semantics for
    ## `grid-rows` / `grid-columns` track lists.
    gtkAuto       ## `auto` — sized to children's intrinsic content
    gtkFixed      ## bare integer cell count, e.g. `3`
    gtkFr         ## `Nfr` — fractional remaining-space share
    gtkPercent    ## `N%` — percentage of available container space

  GridTrack* = object
    ## One row or column track in a `grid-rows` / `grid-columns` list.
    kind*: GridTrackKind
    value*: float64

  GridSize* = object
    ## Result of the `grid-size <cols> [<rows>]` shorthand. `rows == 0`
    ## means "rows are unbounded — auto-flow grows the grid as
    ## children are placed".
    cols*: int
    rows*: int

  GridGutter* = object
    ## Result of the `grid-gutter <horizontal> [<vertical>]` shorthand.
    ## Cells of inter-track gap on each axis.
    horizontal*: int
    vertical*: int

# ----------------------------------------------------------------------------
# Property kind enum + tagged-union value
# ----------------------------------------------------------------------------

type
  PropertyKind* = enum
    ## Properties supported by the M5 cascade. Adding a new property is:
    ## extend this enum, add a parser branch in `parsePropertyValue`,
    ## add a field to the `Styles` cascade output, and an apply branch
    ## in `applyValue`.
    pkWidth
    pkHeight
    pkMinWidth
    pkMinHeight
    pkMaxWidth
    pkMaxHeight
    pkMargin
    pkMarginTop
    pkMarginRight
    pkMarginBottom
    pkMarginLeft
    pkPadding
    pkPaddingTop
    pkPaddingRight
    pkPaddingBottom
    pkPaddingLeft
    pkBorderStyle
    pkBorderColor
    pkBorderTop
    pkBorderRight
    pkBorderBottom
    pkBorderLeft
    pkBorderTitleColor
    pkBorderTitleBackground
    pkBorderTitleStyle
    pkBorderTitleAlign
    pkBorderSubtitleColor
    pkBorderSubtitleBackground
    pkBorderSubtitleStyle
    pkBorderSubtitleAlign
    pkBackground
    pkColor
    pkTint
    pkOpacity
    pkTextStyle
    pkTextAlign
    pkDisplay
    pkVisibility
    pkLayout
    pkDock
    pkOverflow
    pkOverflowX
    pkOverflowY
    pkOffset
    pkOffsetX
    pkOffsetY
    pkAlign
    pkAlignHorizontal
    pkAlignVertical
    pkLayer
    pkLayers
    pkScrollbarSize
    pkScrollbarSizeVertical
    pkScrollbarSizeHorizontal
    pkScrollbarColor
    pkScrollbarBackground
    pkLinkColor
    pkLinkBackground
    pkLinkStyle
    pkGridSize
    pkGridRows
    pkGridColumns
    pkGridGutter
    pkColumnSpan
    pkRowSpan

  ValueKind* = enum
    vkScalar
    vkNumber       ## bare float (used for `opacity`)
    vkEdges
    vkColor
    vkBorderStyle
    vkEdgeBorder   ## border-{top,right,bottom,left}
    vkTextStyle
    vkDisplay
    vkVisibility
    vkLayout
    vkDock
    vkOverflow
    vkTextAlign
    vkOffset
    vkHAlign
    vkVAlign
    vkAlignPair    ## `align: horizontal vertical` — both halves typed
    vkLayer        ## single layer name
    vkLayers       ## ordered list of layer names
    vkInt          ## small non-negative integer (scrollbar-size cells)
    vkGridSize     ## `grid-size <cols> [<rows>]`
    vkGridTracks   ## `grid-rows` / `grid-columns` track list
    vkGridGutter   ## `grid-gutter <horizontal> [<vertical>]`
    vkUnset

  PropertyValue* = object
    ## Tagged-union of all typed values. Stored on the `Styles` object
    ## under one of the typed fields rather than going through this
    ## generic envelope, but the parser produces these so the cascade
    ## merger has a uniform input.
    case kind*: ValueKind
    of vkScalar:      scalarVal*: Scalar
    of vkNumber:      numberVal*: float64
    of vkEdges:       edgesVal*: Edges
    of vkColor:       colorVal*: CssColor
    of vkBorderStyle: borderVal*: BorderStyle
    of vkEdgeBorder:  edgeBorderVal*: EdgeBorder
    of vkTextStyle:   textStyleVal*: set[TextStyleFlag]
    of vkDisplay:     displayVal*: DisplayKind
    of vkVisibility:  visibilityVal*: VisibilityKind
    of vkLayout:      layoutVal*: LayoutKind
    of vkDock:        dockVal*: DockKind
    of vkOverflow:    overflowVal*: OverflowKind
    of vkTextAlign:   textAlignVal*: TextAlignKind
    of vkOffset:      offsetVal*: Offset
    of vkHAlign:      hAlignVal*: HAlignKind
    of vkVAlign:      vAlignVal*: VAlignKind
    of vkAlignPair:
      hAlignPairVal*: HAlignKind
      vAlignPairVal*: VAlignKind
    of vkLayer:       layerVal*: string
    of vkLayers:      layersVal*: seq[string]
    of vkInt:         intVal*: int
    of vkGridSize:    gridSizeVal*: GridSize
    of vkGridTracks:  gridTracksVal*: seq[GridTrack]
    of vkGridGutter:  gridGutterVal*: GridGutter
    of vkUnset:       discard

proc unsetValue*(): PropertyValue {.inline.} =
  PropertyValue(kind: vkUnset)

proc scalarValue*(s: Scalar): PropertyValue {.inline.} =
  PropertyValue(kind: vkScalar, scalarVal: s)

proc edgesValue*(e: Edges): PropertyValue {.inline.} =
  PropertyValue(kind: vkEdges, edgesVal: e)

proc colorValue*(c: CssColor): PropertyValue {.inline.} =
  PropertyValue(kind: vkColor, colorVal: c)

proc borderStyleValue*(b: BorderStyle): PropertyValue {.inline.} =
  PropertyValue(kind: vkBorderStyle, borderVal: b)

proc textStyleValue*(s: set[TextStyleFlag]): PropertyValue {.inline.} =
  PropertyValue(kind: vkTextStyle, textStyleVal: s)

proc displayValue*(d: DisplayKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkDisplay, displayVal: d)

proc visibilityValue*(v: VisibilityKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkVisibility, visibilityVal: v)

proc layoutValue*(l: LayoutKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkLayout, layoutVal: l)

proc dockValue*(d: DockKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkDock, dockVal: d)

proc numberValue*(v: float64): PropertyValue {.inline.} =
  PropertyValue(kind: vkNumber, numberVal: v)

proc edgeBorderValue*(b: EdgeBorder): PropertyValue {.inline.} =
  PropertyValue(kind: vkEdgeBorder, edgeBorderVal: b)

proc overflowValue*(o: OverflowKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkOverflow, overflowVal: o)

proc textAlignValue*(a: TextAlignKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkTextAlign, textAlignVal: a)

proc offsetValue*(o: Offset): PropertyValue {.inline.} =
  PropertyValue(kind: vkOffset, offsetVal: o)

proc hAlignValue*(h: HAlignKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkHAlign, hAlignVal: h)

proc vAlignValue*(v: VAlignKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkVAlign, vAlignVal: v)

proc alignPairValue*(h: HAlignKind; v: VAlignKind): PropertyValue {.inline.} =
  PropertyValue(kind: vkAlignPair, hAlignPairVal: h, vAlignPairVal: v)

proc layerValue*(name: string): PropertyValue {.inline.} =
  PropertyValue(kind: vkLayer, layerVal: name)

proc layersValue*(names: seq[string]): PropertyValue {.inline.} =
  PropertyValue(kind: vkLayers, layersVal: names)

proc intValue*(n: int): PropertyValue {.inline.} =
  PropertyValue(kind: vkInt, intVal: n)

proc gridSizeValue*(g: GridSize): PropertyValue {.inline.} =
  PropertyValue(kind: vkGridSize, gridSizeVal: g)

proc gridTracksValue*(t: seq[GridTrack]): PropertyValue {.inline.} =
  PropertyValue(kind: vkGridTracks, gridTracksVal: t)

proc gridGutterValue*(g: GridGutter): PropertyValue {.inline.} =
  PropertyValue(kind: vkGridGutter, gridGutterVal: g)

# ----------------------------------------------------------------------------
# Property name lookup
# ----------------------------------------------------------------------------

proc propertyKindFromName*(name: string): (bool, PropertyKind) =
  ## Map a CSS declaration name to a `PropertyKind`. Unknown names
  ## return `(false, _)` and the parser drops the declaration with a
  ## warning.
  let lower = name.toLowerAscii
  case lower
  of "width":            (true, pkWidth)
  of "height":           (true, pkHeight)
  of "min-width":        (true, pkMinWidth)
  of "min-height":       (true, pkMinHeight)
  of "max-width":        (true, pkMaxWidth)
  of "max-height":       (true, pkMaxHeight)
  of "margin":           (true, pkMargin)
  of "margin-top":       (true, pkMarginTop)
  of "margin-right":     (true, pkMarginRight)
  of "margin-bottom":    (true, pkMarginBottom)
  of "margin-left":      (true, pkMarginLeft)
  of "padding":          (true, pkPadding)
  of "padding-top":      (true, pkPaddingTop)
  of "padding-right":    (true, pkPaddingRight)
  of "padding-bottom":   (true, pkPaddingBottom)
  of "padding-left":     (true, pkPaddingLeft)
  of "border", "border-style": (true, pkBorderStyle)
  of "border-color":     (true, pkBorderColor)
  of "border-top":       (true, pkBorderTop)
  of "border-right":     (true, pkBorderRight)
  of "border-bottom":    (true, pkBorderBottom)
  of "border-left":      (true, pkBorderLeft)
  of "border-title-color":      (true, pkBorderTitleColor)
  of "border-title-background": (true, pkBorderTitleBackground)
  of "border-title-style":      (true, pkBorderTitleStyle)
  of "border-title-align":      (true, pkBorderTitleAlign)
  of "border-subtitle-color":      (true, pkBorderSubtitleColor)
  of "border-subtitle-background": (true, pkBorderSubtitleBackground)
  of "border-subtitle-style":      (true, pkBorderSubtitleStyle)
  of "border-subtitle-align":      (true, pkBorderSubtitleAlign)
  of "background":       (true, pkBackground)
  of "color":            (true, pkColor)
  of "tint":             (true, pkTint)
  of "opacity":          (true, pkOpacity)
  of "text-style":       (true, pkTextStyle)
  of "text-align":       (true, pkTextAlign)
  of "display":          (true, pkDisplay)
  of "visibility":       (true, pkVisibility)
  of "layout":           (true, pkLayout)
  of "dock":             (true, pkDock)
  of "overflow":         (true, pkOverflow)
  of "overflow-x":       (true, pkOverflowX)
  of "overflow-y":       (true, pkOverflowY)
  of "offset":           (true, pkOffset)
  of "offset-x":         (true, pkOffsetX)
  of "offset-y":         (true, pkOffsetY)
  of "align":            (true, pkAlign)
  of "align-horizontal": (true, pkAlignHorizontal)
  of "align-vertical":   (true, pkAlignVertical)
  of "layer":            (true, pkLayer)
  of "layers":           (true, pkLayers)
  of "scrollbar-size":              (true, pkScrollbarSize)
  of "scrollbar-size-vertical":     (true, pkScrollbarSizeVertical)
  of "scrollbar-size-horizontal":   (true, pkScrollbarSizeHorizontal)
  of "scrollbar-color":      (true, pkScrollbarColor)
  of "scrollbar-background": (true, pkScrollbarBackground)
  of "link-color":       (true, pkLinkColor)
  of "link-background":  (true, pkLinkBackground)
  of "link-style":       (true, pkLinkStyle)
  of "grid-size":        (true, pkGridSize)
  of "grid-rows":        (true, pkGridRows)
  of "grid-columns":     (true, pkGridColumns)
  of "grid-gutter":      (true, pkGridGutter)
  of "column-span":      (true, pkColumnSpan)
  of "row-span":         (true, pkRowSpan)
  else: (false, pkWidth)

proc propertyKindName*(p: PropertyKind): string =
  case p
  of pkWidth: "width"
  of pkHeight: "height"
  of pkMinWidth: "min-width"
  of pkMinHeight: "min-height"
  of pkMaxWidth: "max-width"
  of pkMaxHeight: "max-height"
  of pkMargin: "margin"
  of pkMarginTop: "margin-top"
  of pkMarginRight: "margin-right"
  of pkMarginBottom: "margin-bottom"
  of pkMarginLeft: "margin-left"
  of pkPadding: "padding"
  of pkPaddingTop: "padding-top"
  of pkPaddingRight: "padding-right"
  of pkPaddingBottom: "padding-bottom"
  of pkPaddingLeft: "padding-left"
  of pkBorderStyle: "border-style"
  of pkBorderColor: "border-color"
  of pkBorderTop: "border-top"
  of pkBorderRight: "border-right"
  of pkBorderBottom: "border-bottom"
  of pkBorderLeft: "border-left"
  of pkBorderTitleColor: "border-title-color"
  of pkBorderTitleBackground: "border-title-background"
  of pkBorderTitleStyle: "border-title-style"
  of pkBorderTitleAlign: "border-title-align"
  of pkBorderSubtitleColor: "border-subtitle-color"
  of pkBorderSubtitleBackground: "border-subtitle-background"
  of pkBorderSubtitleStyle: "border-subtitle-style"
  of pkBorderSubtitleAlign: "border-subtitle-align"
  of pkBackground: "background"
  of pkColor: "color"
  of pkTint: "tint"
  of pkOpacity: "opacity"
  of pkTextStyle: "text-style"
  of pkTextAlign: "text-align"
  of pkDisplay: "display"
  of pkVisibility: "visibility"
  of pkLayout: "layout"
  of pkDock: "dock"
  of pkOverflow: "overflow"
  of pkOverflowX: "overflow-x"
  of pkOverflowY: "overflow-y"
  of pkOffset: "offset"
  of pkOffsetX: "offset-x"
  of pkOffsetY: "offset-y"
  of pkAlign: "align"
  of pkAlignHorizontal: "align-horizontal"
  of pkAlignVertical: "align-vertical"
  of pkLayer: "layer"
  of pkLayers: "layers"
  of pkScrollbarSize: "scrollbar-size"
  of pkScrollbarSizeVertical: "scrollbar-size-vertical"
  of pkScrollbarSizeHorizontal: "scrollbar-size-horizontal"
  of pkScrollbarColor: "scrollbar-color"
  of pkScrollbarBackground: "scrollbar-background"
  of pkLinkColor: "link-color"
  of pkLinkBackground: "link-background"
  of pkLinkStyle: "link-style"
  of pkGridSize: "grid-size"
  of pkGridRows: "grid-rows"
  of pkGridColumns: "grid-columns"
  of pkGridGutter: "grid-gutter"
  of pkColumnSpan: "column-span"
  of pkRowSpan: "row-span"

# ----------------------------------------------------------------------------
# Keyword parsers
# ----------------------------------------------------------------------------

proc parseDisplay*(s: string): (bool, DisplayKind) =
  case s.toLowerAscii
  of "block": (true, dkBlock)
  of "none":  (true, dkNone)
  else:       (false, dkBlock)

proc parseVisibility*(s: string): (bool, VisibilityKind) =
  case s.toLowerAscii
  of "visible": (true, vkVisible)
  of "hidden":  (true, vkHidden)
  else:         (false, vkVisible)

proc parseLayout*(s: string): (bool, LayoutKind) =
  case s.toLowerAscii
  of "vertical":   (true, lkVertical)
  of "horizontal": (true, lkHorizontal)
  of "grid":       (true, lkGrid)
  of "stream":     (true, lkStream)
  else:            (false, lkVertical)

proc parseDock*(s: string): (bool, DockKind) =
  case s.toLowerAscii
  of "top":    (true, dockTop)
  of "bottom": (true, dockBottom)
  of "left":   (true, dockLeft)
  of "right":  (true, dockRight)
  of "none":   (true, dockNone)
  else:        (false, dockNone)

proc parseBorderStyle*(s: string): (bool, BorderStyle) =
  case s.toLowerAscii
  of "":       (true, bsNone)
  of "none":   (true, bsNone)
  of "ascii":  (true, bsAscii)
  of "hidden": (true, bsHidden)
  of "blank":  (true, bsBlank)
  of "round":  (true, bsRound)
  of "solid":  (true, bsSolid)
  of "double": (true, bsDouble)
  of "dashed": (true, bsDashed)
  of "heavy":  (true, bsHeavy)
  of "inner":  (true, bsInner)
  of "outer":  (true, bsOuter)
  of "thick":  (true, bsThick)
  of "block":  (true, bsBlock)
  of "hkey":   (true, bsHkey)
  of "vkey":   (true, bsVkey)
  of "tall":   (true, bsTall)
  of "panel":  (true, bsPanel)
  of "tab":    (true, bsTab)
  of "wide":   (true, bsWide)
  else:        (false, bsNone)

proc parseTextStyleFlag*(s: string): (bool, TextStyleFlag) =
  case s.toLowerAscii
  of "bold":      (true, tsBold)
  of "italic":    (true, tsItalic)
  of "underline": (true, tsUnderline)
  of "strike":    (true, tsStrike)
  of "reverse":   (true, tsReverse)
  of "dim":       (true, tsDim)
  of "blink":     (true, tsBlink)
  of "overline":  (true, tsOverline)
  else:           (false, tsBold)

proc parseOverflow*(s: string): (bool, OverflowKind) =
  case s.toLowerAscii
  of "visible": (true, ovVisible)
  of "hidden":  (true, ovHidden)
  of "scroll":  (true, ovScroll)
  of "auto":    (true, ovAuto)
  else:         (false, ovVisible)

proc parseTextAlign*(s: string): (bool, TextAlignKind) =
  case s.toLowerAscii
  of "left":    (true, taLeft)
  of "center":  (true, taCenter)
  of "centre":  (true, taCenter)   ## Textual accepts both spellings
  of "right":   (true, taRight)
  of "justify": (true, taJustify)
  of "start":   (true, taStart)
  of "end":     (true, taEnd)
  else:         (false, taLeft)

proc parseHAlign*(s: string): (bool, HAlignKind) =
  case s.toLowerAscii
  of "left":   (true, haLeft)
  of "center": (true, haCenter)
  of "centre": (true, haCenter)
  of "right":  (true, haRight)
  else:        (false, haLeft)

proc parseVAlign*(s: string): (bool, VAlignKind) =
  case s.toLowerAscii
  of "top":    (true, vaTop)
  of "middle": (true, vaMiddle)
  of "center": (true, vaMiddle)
  of "centre": (true, vaMiddle)
  of "bottom": (true, vaBottom)
  else:        (false, vaTop)
