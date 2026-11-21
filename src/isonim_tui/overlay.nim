## Overlay — a rectangle that re-colours already-composited cells.
##
## A drop zone, a hover highlight, a "this is where it would go" tint: things a
## GUI draws as a translucent rectangle over the content. A terminal cell has no
## alpha, so the equivalent is to CHANGE THE COLOURS of the cells underneath —
## blend their foreground and background toward a tint — and leave their
## glyphs alone, so the text under the highlight stays readable and the
## highlight says only "here".
##
## ## As a node
##
## An overlay is a box the compositor treats as out of flow:
##
##     <div style="overlay: tint; top: 3; left: 10; width: 20; height: 5;
##                 overlay-color: #5a9dd4; overlay-alpha: 0.35;
##                 overlay-reverse: false; layer: 5">
##
## * `top` / `left` / `width` / `height` — the rectangle, in cells, absolute
##   in the screen (it takes no row of the flow layout).
## * `overlay-color` — the tint, `#RRGGBB`.
## * `overlay-alpha` — how far every colour moves toward the tint, 0..1.
## * `overlay-reverse` — additionally toggle reverse video (the monochrome
##   answer, where there are no colours to blend).
## * `overlay-base-fg` / `overlay-base-bg` — the colours a cell with the
##   terminal's DEFAULT foreground / background actually shows (the caller
##   knows its theme; the compositor cannot ask the terminal). Without them a
##   default colour blends from black / white.
## * `overlay-depth` — `truecolor` (default), `256`, `16` or `mono`: the
##   blended colour is quantised to the xterm 256 palette or the 16 ANSI
##   colours, so an overlay never emits a colour the terminal cannot show —
##   and where the palette is too coarse for the blend to show at all, the
##   blend is strengthened until it does; `mono` blends nothing and only
##   reverses.
## * `layer` — the z-order. The compositor applies an overlay after every
##   entry that precedes it in paint order (lower layers, then earlier nodes
##   of the same layer) and before everything after it, so a label at a
##   higher layer is drawn over the tint, untinted.
##
## `overlayNode` builds one; `applyOverlay` is the operation itself, exported
## so it can be tested on a buffer directly.
##
## Glyphs, widths and attributes other than reverse are NEVER touched: a wide
## glyph's two cells are re-coloured together and stay a pair.

import std/[math, strutils, tables]

import ./cells
import ./renderer

type
  OverlayDepth* = enum
    odTrueColor = "truecolor"
    od256 = "256"
    od16 = "16"
    odMono = "mono"

  OverlaySpec* = object
    ## One overlay, as a value.
    top*, left*, width*, height*: int
    color*: Color          ## the tint (RGB)
    alpha*: float          ## 0..1
    reverse*: bool
    baseFg*: Color         ## what a default foreground shows (RGB or default)
    baseBg*: Color         ## what a default background shows (RGB or default)
    depth*: OverlayDepth
    layer*: int

# ----------------------------------------------------------------------------
# Palettes
# ----------------------------------------------------------------------------

const
  Ansi16Rgb*: array[16, (uint8, uint8, uint8)] = [
    (0'u8, 0'u8, 0'u8), (205'u8, 0'u8, 0'u8), (0'u8, 205'u8, 0'u8),
    (205'u8, 205'u8, 0'u8), (0'u8, 0'u8, 238'u8), (205'u8, 0'u8, 205'u8),
    (0'u8, 205'u8, 205'u8), (229'u8, 229'u8, 229'u8),
    (127'u8, 127'u8, 127'u8), (255'u8, 0'u8, 0'u8), (0'u8, 255'u8, 0'u8),
    (255'u8, 255'u8, 0'u8), (92'u8, 92'u8, 255'u8), (255'u8, 0'u8, 255'u8),
    (0'u8, 255'u8, 255'u8), (255'u8, 255'u8, 255'u8)]
    ## xterm's default 16 colours — the reference a blended ANSI colour is
    ## computed from and quantised back to.

func xterm256Rgb*(idx: uint8): (uint8, uint8, uint8) =
  ## The RGB of an xterm 256-colour palette entry.
  let i = int(idx)
  if i < 16:
    return Ansi16Rgb[i]
  if i < 232:
    let n = i - 16
    const steps = [0, 95, 135, 175, 215, 255]
    return (uint8(steps[n div 36]), uint8(steps[(n div 6) mod 6]),
            uint8(steps[n mod 6]))
  let v = uint8(8 + (i - 232) * 10)
  (v, v, v)

func dist2(a, b: (uint8, uint8, uint8)): int =
  let dr = int(a[0]) - int(b[0])
  let dg = int(a[1]) - int(b[1])
  let db = int(a[2]) - int(b[2])
  dr * dr + dg * dg + db * db

func nearest256*(rgb: (uint8, uint8, uint8)): uint8 =
  ## The nearest xterm 256 palette entry (16..255; the first 16 are the
  ## user's own and vary by terminal).
  var best = 16
  var bestD = high(int)
  for i in 16 .. 255:
    let d = dist2(rgb, xterm256Rgb(uint8(i)))
    if d < bestD:
      bestD = d
      best = i
  uint8(best)

func nearestAnsi16*(rgb: (uint8, uint8, uint8)): AnsiColor =
  var best = 0
  var bestD = high(int)
  for i in 0 .. 15:
    let d = dist2(rgb, Ansi16Rgb[i])
    if d < bestD:
      bestD = d
      best = i
  AnsiColor(best)

func rgbOf*(c: Color; fallback: (uint8, uint8, uint8)): (uint8, uint8, uint8) =
  ## A colour's RGB; `fallback` for the terminal default.
  case c.kind
  of ckRgb: (c.r, c.g, c.b)
  of ckAnsi: Ansi16Rgb[ord(c.ansi) and 15]
  of ckIndexed: xterm256Rgb(c.indexed)
  of ckDefault: fallback

func blendRgb*(a, b: (uint8, uint8, uint8); alpha: float): (uint8, uint8, uint8) =
  ## `a` moved `alpha` of the way toward `b`.
  let t = clamp(alpha, 0.0, 1.0)
  proc mix(x, y: uint8): uint8 =
    uint8(clamp(round(float(x) * (1.0 - t) + float(y) * t), 0.0, 255.0))
  (mix(a[0], b[0]), mix(a[1], b[1]), mix(a[2], b[2]))

func quantise(rgb: (uint8, uint8, uint8); depth: OverlayDepth): Color =
  case depth
  of odTrueColor, odMono: rgbColor(rgb[0], rgb[1], rgb[2])
  of od256: indexedColor(nearest256(rgb))
  of od16: ansiColor(nearestAnsi16(rgb))

# ----------------------------------------------------------------------------
# The operation
# ----------------------------------------------------------------------------

proc tintCell*(cell: Cell; spec: OverlaySpec): Cell =
  ## One cell under an overlay: same glyph, colours blended toward the tint.
  result = cell
  if spec.depth != odMono:
    let tint = rgbOf(spec.color, (0'u8, 0'u8, 0'u8))
    let fgBase = rgbOf(cell.fg, rgbOf(spec.baseFg, (255'u8, 255'u8, 255'u8)))
    let bgBase = rgbOf(cell.bg, rgbOf(spec.baseBg, (0'u8, 0'u8, 0'u8)))
    # A COARSE PALETTE CAN SWALLOW A LIGHT TINT: 35% of a blue over a near-
    # black ground is still ANSI black. So the blend is strengthened, in
    # steps, until the quantised background differs from the cell's own —
    # an overlay that changes nothing visible would be a highlight that is
    # not there. In truecolor the first step already differs.
    let unchanged = quantise(bgBase, spec.depth)
    var a = spec.alpha
    var bg = quantise(blendRgb(bgBase, tint, a), spec.depth)
    while bg == unchanged and a < 1.0:
      a = min(1.0, a + 0.15)
      bg = quantise(blendRgb(bgBase, tint, a), spec.depth)
    result.bg = bg
    result.fg = quantise(blendRgb(fgBase, tint, spec.alpha * 0.5), spec.depth)
  if spec.reverse or spec.depth == odMono:
    if attrReverse in result.attrs: result.attrs.excl attrReverse
    else: result.attrs.incl attrReverse

proc applyOverlay*(buf: var ScreenBuffer; spec: OverlaySpec) =
  ## Re-colour every cell of `spec`'s rectangle that lies on the buffer.
  ## Glyphs are untouched; a wide glyph's leading half and its ghost are
  ## re-coloured together (a rectangle edge through a wide glyph takes the
  ## whole glyph).
  let top = max(0, spec.top)
  let bottom = min(buf.rowsCount, spec.top + max(0, spec.height))
  for r in top ..< bottom:
    var row = buf.rows[r]
    let left = max(0, spec.left)
    let right = min(row.cells.len, spec.left + max(0, spec.width))
    var c = left
    # A rectangle starting on a ghost cell starts at its wide glyph.
    if c > 0 and c < row.cells.len and row.cells[c].width == 0:
      dec c
    while c < right:
      row.cells[c] = tintCell(row.cells[c], spec)
      if row.cells[c].width == 2 and c + 1 < row.cells.len:
        row.cells[c + 1] = tintCell(row.cells[c + 1], spec)
        c += 2
      else:
        inc c
    recomputeCache(row)
    buf.rows[r] = row

# ----------------------------------------------------------------------------
# As a node, and back
# ----------------------------------------------------------------------------

func hexOf(c: Color): string =
  if c.kind != ckRgb: return ""
  "#" & toHex(int(c.r), 2).toLowerAscii & toHex(int(c.g), 2).toLowerAscii &
    toHex(int(c.b), 2).toLowerAscii

proc overlayNode*(r: TerminalRenderer; spec: OverlaySpec): TerminalNode =
  ## A node the compositor applies as `spec` (see the module header).
  result = r.createElement("div")
  r.setStyle(result, "overlay", "tint")
  r.setStyle(result, "top", $spec.top)
  r.setStyle(result, "left", $spec.left)
  r.setStyle(result, "width", $spec.width)
  r.setStyle(result, "height", $spec.height)
  r.setStyle(result, "overlay-color", hexOf(spec.color))
  r.setStyle(result, "overlay-alpha", $spec.alpha)
  r.setStyle(result, "overlay-reverse", (if spec.reverse: "true" else: "false"))
  if spec.baseFg.kind == ckRgb:
    r.setStyle(result, "overlay-base-fg", hexOf(spec.baseFg))
  if spec.baseBg.kind == ckRgb:
    r.setStyle(result, "overlay-base-bg", hexOf(spec.baseBg))
  r.setStyle(result, "overlay-depth", $spec.depth)
  r.setStyle(result, "layer", $spec.layer)

proc parseHexColor(s: string): Color =
  if s.len == 7 and s[0] == '#':
    try:
      return rgbColor(uint8(parseHexInt(s[1 .. 2])), uint8(parseHexInt(s[3 .. 4])),
                      uint8(parseHexInt(s[5 .. 6])))
    except ValueError:
      discard
  defaultColor()

proc isOverlayNode*(node: TerminalNode): bool =
  node != nil and node.styles.getOrDefault("overlay", "") == "tint"

proc overlaySpecOf*(node: TerminalNode; layer: int): OverlaySpec =
  ## The spec an overlay node carries; `layer` is the node's resolved layer.
  proc intOf(name: string): int =
    try: parseInt(node.styles.getOrDefault(name, "0"))
    except ValueError: 0
  result.top = intOf("top")
  result.left = intOf("left")
  result.width = intOf("width")
  result.height = intOf("height")
  result.color = parseHexColor(node.styles.getOrDefault("overlay-color", ""))
  try:
    result.alpha = parseFloat(node.styles.getOrDefault("overlay-alpha", "0.35"))
  except ValueError:
    result.alpha = 0.35
  result.reverse = node.styles.getOrDefault("overlay-reverse", "") == "true"
  result.baseFg = parseHexColor(node.styles.getOrDefault("overlay-base-fg", ""))
  result.baseBg = parseHexColor(node.styles.getOrDefault("overlay-base-bg", ""))
  result.depth =
    case node.styles.getOrDefault("overlay-depth", "truecolor")
    of "256": od256
    of "16": od16
    of "mono": odMono
    else: odTrueColor
  result.layer = layer
