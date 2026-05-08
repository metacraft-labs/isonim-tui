## widgets/sparkline.nim — Tier-3e `Sparkline` widget (M21).
##
## Port of `textual/_renderables/sparkline.py` plus the thin widget
## wrapper from `textual/widgets/_sparkline.py`. A sparkline is a
## compact one-line (or N-line) chart of a numeric series, drawn with
## the eight Unicode block glyphs `▁▂▃▄▅▆▇█`. The renderer partitions
## the input data into `width` buckets, applies a summary function
## (default `max`), then maps each bucket's summary onto the available
## bar height.
##
## *Optional gradient*: callers can supply two colours (`minColor`,
## `maxColor`) and the widget linearly interpolates the bar colour
## between them based on the bucket's height ratio. The default skips
## colouring (uses the inherited foreground).
##
## Charter §1: every public type is a value object; the widget itself
## is `ref` so callers can swap data with `setData`.

import std/[strutils]

import ../renderer

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

const SparklineBars* = [
  "\xE2\x96\x81",  # ▁ 1/8
  "\xE2\x96\x82",  # ▂ 2/8
  "\xE2\x96\x83",  # ▃ 3/8
  "\xE2\x96\x84",  # ▄ 4/8
  "\xE2\x96\x85",  # ▅ 5/8
  "\xE2\x96\x86",  # ▆ 6/8
  "\xE2\x96\x87",  # ▇ 7/8
  "\xE2\x96\x88",  # █ 8/8
]

type
  SparklineSummary* = enum
    sumMax
    sumMin
    sumMean
    sumLast
    sumFirst

  SparklineWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    data*: seq[float64]
    width*: int                 ## Bucket count == drawn cell count.
    height*: int                ## Output height in lines.
    summary*: SparklineSummary
    minColor*: string           ## Optional gradient endpoint (low).
    maxColor*: string           ## Optional gradient endpoint (high).

# ----------------------------------------------------------------------------
# Forward decl
# ----------------------------------------------------------------------------
proc renderTree*(s: SparklineWidget)

# ----------------------------------------------------------------------------
# Tree builder helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "") =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

# ----------------------------------------------------------------------------
# Bucketing + summary
# ----------------------------------------------------------------------------

proc bucketsOf(s: SparklineWidget): seq[seq[float64]] =
  ## Partition `data` into `width` contiguous slices. Empty inputs
  ## produce an empty result (rendered as the floor row of '▁').
  let n = s.data.len
  if n == 0 or s.width <= 0: return @[]
  let buckets = s.width
  result = newSeq[seq[float64]](buckets)
  for i in 0 ..< buckets:
    let startIdx = (i * n) div buckets
    let endIdx = ((i + 1) * n) div buckets
    if startIdx >= endIdx:
      # Reuse the last value so every bucket has at least one sample.
      let fallback =
        if i > 0 and result[i - 1].len > 0: result[i - 1][^1]
        else: s.data[min(startIdx, n - 1)]
      result[i] = @[fallback]
    else:
      result[i] = s.data[startIdx ..< endIdx]

proc summarise(b: seq[float64]; how: SparklineSummary): float64 =
  if b.len == 0: return 0.0
  case how
  of sumMax:
    var v = b[0]
    for x in b: (if x > v: v = x)
    v
  of sumMin:
    var v = b[0]
    for x in b: (if x < v: v = x)
    v
  of sumMean:
    var sum = 0.0
    for x in b: sum += x
    sum / b.len.float64
  of sumLast: b[^1]
  of sumFirst: b[0]

# ----------------------------------------------------------------------------
# Gradient blender (textual/_blend_colors.py — simplified for named
# CSS strings the M8 compositor recognises). When either gradient
# endpoint is empty, no colour is applied.
# ----------------------------------------------------------------------------

proc gradientForRatio(s: SparklineWidget; ratio: float64): string =
  ## Picks the colour for a bar at fractional height `ratio` in [0, 1].
  ## The simplified gradient: at ratio < 0.5 use `minColor`; >= 0.5 use
  ## `maxColor`. (A full RGB blend is a follow-up to the M21 surface;
  ## the inline-style table only accepts a single named colour today.)
  if s.minColor.len == 0 and s.maxColor.len == 0: return ""
  if ratio >= 0.5 and s.maxColor.len > 0: return s.maxColor
  if s.minColor.len > 0: return s.minColor
  s.maxColor

# ----------------------------------------------------------------------------
# Renderer
# ----------------------------------------------------------------------------

proc renderTree*(s: SparklineWidget) =
  let r = s.renderer
  clearTreeChildren(r, s.node)
  let height = max(1, s.height)
  let width = max(0, s.width)

  # Empty / single-sample fast paths mirror the Textual renderable.
  if s.data.len == 0:
    for _ in 0 ..< height - 1:
      emitRow(r, s.node, repeat(' ', width), s.minColor)
    emitRow(r, s.node, repeat(SparklineBars[0], width), s.minColor)
    return

  if s.data.len == 1:
    for _ in 0 ..< height:
      emitRow(r, s.node, repeat("\xE2\x96\x88", width), s.maxColor)
    return

  let buckets = s.bucketsOf
  if buckets.len == 0:
    return

  # Find min / max across the *summarised* bucket values so single-row
  # rendering matches the multi-row case visually.
  var mn = high(float64)
  var mx = low(float64)
  var summaries = newSeq[float64](buckets.len)
  for i, b in buckets:
    let v = summarise(b, s.summary)
    summaries[i] = v
    if v < mn: mn = v
    if v > mx: mx = v
  let extent = (
    if mx - mn == 0.0: 1.0
    else: mx - mn)

  let bars = SparklineBars.len            # 8
  let segmentsTotal = bars * height - 1   # mirrors the Python algorithm

  # Render rows top to bottom.
  for rowIdx in countdown(height - 1, 0):
    var line = ""
    let lowSegment = rowIdx * bars
    let highSegment = (rowIdx + 1) * bars
    var lastColor = ""
    for ci in 0 ..< buckets.len:
      let v = summaries[ci]
      let ratio = (v - mn) / extent
      let barIndex = int(ratio * segmentsTotal.float64)
      var glyph: string
      var withColor: bool
      if barIndex < lowSegment:
        glyph = " "
        withColor = false
      elif barIndex >= highSegment:
        glyph = "\xE2\x96\x88" # full block
        withColor = true
      else:
        glyph = SparklineBars[barIndex mod bars]
        withColor = true
      line.add glyph
      if withColor:
        lastColor = s.gradientForRatio(ratio)
    emitRow(r, s.node, line, lastColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newSparkline*(renderer: TerminalRenderer;
                   data: openArray[float64] = [];
                   width: int = 20;
                   height: int = 1;
                   summary: SparklineSummary = sumMax;
                   minColor: string = "";
                   maxColor: string = ""): SparklineWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "sparkline")
  renderer.setAttribute(node, "class", "sparkline")
  var d: seq[float64] = @[]
  for v in data: d.add v
  let s = SparklineWidget(
    renderer: renderer, node: node,
    data: d,
    width: max(1, width),
    height: max(1, height),
    summary: summary,
    minColor: minColor, maxColor: maxColor)
  s.renderTree()
  s

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc setData*(s: SparklineWidget; data: openArray[float64]) =
  var d: seq[float64] = @[]
  for v in data: d.add v
  s.data = d
  s.renderTree()

proc appendValue*(s: SparklineWidget; value: float64;
                  retainCount: int = 0) =
  ## Append a single sample. If `retainCount` > 0, prune the oldest
  ## values so the history stays bounded (handy for live metrics).
  s.data.add value
  if retainCount > 0 and s.data.len > retainCount:
    let drop = s.data.len - retainCount
    for i in 0 ..< s.data.len - drop:
      s.data[i] = s.data[i + drop]
    s.data.setLen(s.data.len - drop)
  s.renderTree()

proc setSummary*(s: SparklineWidget; how: SparklineSummary) =
  s.summary = how
  s.renderTree()

proc id*(s: SparklineWidget): int {.inline.} = s.node.id
