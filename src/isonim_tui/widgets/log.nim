## widgets/log.nim — Tier-3e `Log` widget (M21).
##
## Port of `textual/widgets/_log.py` (~362 LOC). A plain-text relative
## of `RichLog`: same ring-buffer + auto-follow shape, but no inline
## colour metadata. This is the workhorse for tail-style log views
## where every line shares the widget's default style.
##
## The implementation deliberately mirrors `rich_log.nim` so the two
## widgets present a near-identical surface to callers; the only
## difference is that `Log` accepts plain strings (no per-line colour
## override) which keeps the hot-path append cheaper for noisy logs.

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  LogWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    lines*: seq[string]
    maxLines*: int                  ## 0 = unbounded.
    width*: int
    viewportHeight*: int
    scrollY*: int
    autoFollow*: bool
    border*: BorderStyle
    borderColor*: string
    color*: string

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(lg: LogWidget)
proc scrollEnd*(lg: LogWidget)
proc scrollHome*(lg: LogWidget)
proc pageUp*(lg: LogWidget)
proc pageDown*(lg: LogWidget)
proc lineUp*(lg: LogWidget)
proc lineDown*(lg: LogWidget)

# ----------------------------------------------------------------------------
# Tree builder
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

proc maxScroll(lg: LogWidget): int {.inline.} =
  max(0, lg.lines.len - lg.viewportHeight)

proc isAtBottom*(lg: LogWidget): bool {.inline.} =
  lg.scrollY >= lg.maxScroll

proc renderTree*(lg: LogWidget) =
  let r = lg.renderer
  clearTreeChildren(r, lg.node)
  let glyphs = bordersGlyphs(lg.border)
  let useBorder = lg.border != bsNone
  if useBorder:
    emitRow(r, lg.node, topBorderRow(glyphs, lg.width), lg.borderColor)
  let visible = max(0, min(lg.lines.len - lg.scrollY, lg.viewportHeight))
  for i in 0 ..< visible:
    let body = padOrTruncate(lg.lines[lg.scrollY + i], lg.width)
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, lg.node, row, lg.color)
  for _ in visible ..< lg.viewportHeight:
    let body = spaces(lg.width)
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, lg.node, row, lg.borderColor)
  if useBorder:
    emitRow(r, lg.node, bottomBorderRow(glyphs, lg.width), lg.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newLog*(renderer: TerminalRenderer;
             width: int = 40;
             viewportHeight: int = 10;
             maxLines: int = 0;
             autoFollow: bool = true;
             border: BorderStyle = bsNone;
             borderColor: string = "";
             color: string = ""): LogWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "log")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "log")
  let lg = LogWidget(
    renderer: renderer, node: node,
    lines: @[],
    maxLines: max(0, maxLines),
    width: max(1, width),
    viewportHeight: max(1, viewportHeight),
    scrollY: 0,
    autoFollow: autoFollow,
    border: border, borderColor: borderColor, color: color)
  lg.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "down", "Down":               lg.lineDown()
    of "up", "Up":                   lg.lineUp()
    of "pagedown", "PageDown", "pageDown": lg.pageDown()
    of "pageup", "PageUp", "pageUp":       lg.pageUp()
    of "home", "Home":               lg.scrollHome()
    of "end", "End":                 lg.scrollEnd()
    else: discard)
  lg

# ----------------------------------------------------------------------------
# Internal trim
# ----------------------------------------------------------------------------

proc trimToMax(lg: LogWidget) =
  if lg.maxLines <= 0: return
  if lg.lines.len <= lg.maxLines: return
  let drop = lg.lines.len - lg.maxLines
  for i in 0 ..< lg.lines.len - drop:
    lg.lines[i] = lg.lines[i + drop]
  lg.lines.setLen(lg.lines.len - drop)
  lg.scrollY = max(0, lg.scrollY - drop)

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc writeLine*(lg: LogWidget; text: string) =
  ## Append exactly one line. Embedded `\n` is preserved as a literal —
  ## use `write` for multi-line input.
  let stickyBottom = lg.isAtBottom
  lg.lines.add text
  lg.trimToMax()
  if lg.autoFollow and stickyBottom:
    lg.scrollY = lg.maxScroll
  lg.renderTree()

proc write*(lg: LogWidget; text: string) =
  ## Append `text`, splitting on `\n`. Each substring becomes its own
  ## log line; auto-follow honours the bottom sticky-bit policy.
  let stickyBottom = lg.isAtBottom
  if text.len == 0:
    lg.lines.add ""
  else:
    var start = 0
    for i in 0 .. text.high:
      if text[i] == '\n':
        lg.lines.add text[start ..< i]
        start = i + 1
    lg.lines.add text[start .. text.high]
  lg.trimToMax()
  if lg.autoFollow and stickyBottom:
    lg.scrollY = lg.maxScroll
  lg.renderTree()

proc writeLines*(lg: LogWidget; texts: openArray[string]) =
  let stickyBottom = lg.isAtBottom
  for t in texts:
    lg.lines.add t
  lg.trimToMax()
  if lg.autoFollow and stickyBottom:
    lg.scrollY = lg.maxScroll
  lg.renderTree()

proc clear*(lg: LogWidget) =
  lg.lines.setLen(0)
  lg.scrollY = 0
  lg.renderTree()

proc scrollEnd*(lg: LogWidget) =
  lg.scrollY = lg.maxScroll
  lg.autoFollow = true
  lg.renderTree()

proc scrollHome*(lg: LogWidget) =
  lg.scrollY = 0
  lg.autoFollow = false
  lg.renderTree()

proc pageUp*(lg: LogWidget) =
  let step = max(1, lg.viewportHeight - 1)
  lg.scrollY = max(0, lg.scrollY - step)
  lg.autoFollow = false
  lg.renderTree()

proc pageDown*(lg: LogWidget) =
  let step = max(1, lg.viewportHeight - 1)
  lg.scrollY = min(lg.maxScroll, lg.scrollY + step)
  if lg.scrollY >= lg.maxScroll:
    lg.autoFollow = true
  lg.renderTree()

proc lineUp*(lg: LogWidget) =
  if lg.scrollY > 0:
    dec lg.scrollY
    lg.autoFollow = false
    lg.renderTree()

proc lineDown*(lg: LogWidget) =
  if lg.scrollY < lg.maxScroll:
    inc lg.scrollY
    if lg.scrollY >= lg.maxScroll:
      lg.autoFollow = true
    lg.renderTree()

proc id*(lg: LogWidget): int {.inline.} = lg.node.id
