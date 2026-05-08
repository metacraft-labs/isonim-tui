## widgets/rich_log.nim — Tier-3e `RichLog` widget (M21).
##
## Port of `textual/widgets/_rich_log.py` (~320 LOC). An append-mostly
## scrollable log buffer optimised for streaming text. Lines are stored
## in a ring-buffer (when `maxLines > 0`) so memory stays bounded as
## logs grow without bound. The widget tracks an *auto-follow* flag —
## when the viewport is at the bottom, every new `write()` keeps it at
## the bottom; when the user scrolls up, new writes append silently
## without disturbing the visible window. Pressing `End` re-engages
## auto-follow.
##
## *Optional content tier*: each line carries an inline colour string
## so callers can pre-style log entries (`write("[ERROR]", color="red")`).
## Full Rich-style markup parsing is deferred to a follow-up; the M21
## surface accepts plain strings + an optional inline colour.
##
## Charter §1: every public type is a value object; the widget handle
## itself is a `ref` so callers can mutate state directly.

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  RichLogLine* = object
    ## A single log entry. `color` is empty when the line should render
    ## with the default foreground.
    text*: string
    color*: string

  RichLogWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    lines*: seq[RichLogLine]        ## Ring-buffered log entries.
    maxLines*: int                  ## 0 = unbounded.
    width*: int                     ## Inner width in cells.
    viewportHeight*: int
    scrollY*: int                   ## Top visible line index.
    autoFollow*: bool               ## Sticks to bottom when true.
    border*: BorderStyle
    borderColor*: string
    color*: string                  ## Default text colour.
    wrap*: bool

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(rl: RichLogWidget)
proc scrollEnd*(rl: RichLogWidget)
proc scrollHome*(rl: RichLogWidget)
proc pageUp*(rl: RichLogWidget)
proc pageDown*(rl: RichLogWidget)
proc lineUp*(rl: RichLogWidget)
proc lineDown*(rl: RichLogWidget)

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

proc maxScroll(rl: RichLogWidget): int {.inline.} =
  ## The largest valid scrollY value: the index of the first line in a
  ## viewport-sized window that ends on the last line.
  max(0, rl.lines.len - rl.viewportHeight)

proc isAtBottom*(rl: RichLogWidget): bool {.inline.} =
  ## True when the viewport currently shows the last line. Tests query
  ## this to assert the auto-follow contract.
  rl.scrollY >= rl.maxScroll

proc renderTree*(rl: RichLogWidget) =
  let r = rl.renderer
  clearTreeChildren(r, rl.node)
  let glyphs = bordersGlyphs(rl.border)
  let useBorder = rl.border != bsNone
  if useBorder:
    emitRow(r, rl.node, topBorderRow(glyphs, rl.width), rl.borderColor)
  let visible = max(0, min(rl.lines.len - rl.scrollY, rl.viewportHeight))
  for i in 0 ..< visible:
    let line = rl.lines[rl.scrollY + i]
    let body = padOrTruncate(line.text, rl.width)
    let lineColor =
      if line.color.len > 0: line.color
      else: rl.color
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, rl.node, row, lineColor)
  for _ in visible ..< rl.viewportHeight:
    let body = spaces(rl.width)
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, rl.node, row, rl.borderColor)
  if useBorder:
    emitRow(r, rl.node, bottomBorderRow(glyphs, rl.width), rl.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newRichLog*(renderer: TerminalRenderer;
                 width: int = 40;
                 viewportHeight: int = 10;
                 maxLines: int = 0;
                 autoFollow: bool = true;
                 wrap: bool = false;
                 border: BorderStyle = bsNone;
                 borderColor: string = "";
                 color: string = ""): RichLogWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "rich-log")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "rich-log")
  let rl = RichLogWidget(
    renderer: renderer, node: node,
    lines: @[],
    maxLines: max(0, maxLines),
    width: max(1, width),
    viewportHeight: max(1, viewportHeight),
    scrollY: 0,
    autoFollow: autoFollow,
    border: border, borderColor: borderColor, color: color,
    wrap: wrap)
  rl.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "down", "Down":               rl.lineDown()
    of "up", "Up":                   rl.lineUp()
    of "pagedown", "PageDown", "pageDown": rl.pageDown()
    of "pageup", "PageUp", "pageUp":       rl.pageUp()
    of "home", "Home":               rl.scrollHome()
    of "end", "End":                 rl.scrollEnd()
    else: discard)
  rl

# ----------------------------------------------------------------------------
# Internal: trim ring buffer and re-clamp scroll position.
# ----------------------------------------------------------------------------

proc trimToMax(rl: RichLogWidget) =
  if rl.maxLines <= 0: return
  if rl.lines.len <= rl.maxLines: return
  let drop = rl.lines.len - rl.maxLines
  # Drop the first `drop` entries — done by shifting and shrinking, so
  # we don't depend on stdlib `delete` slice variants (which Nim 2.2.4
  # only exposes through `system.delete(x, Natural)`).
  for i in 0 ..< rl.lines.len - drop:
    rl.lines[i] = rl.lines[i + drop]
  rl.lines.setLen(rl.lines.len - drop)
  # When we drop from the head, the visible window's absolute index
  # shifts. If we were at scrollY=k, the equivalent post-drop position
  # is max(0, k - drop). When auto-following we always recompute below.
  rl.scrollY = max(0, rl.scrollY - drop)

# ----------------------------------------------------------------------------
# Public mutators — write / clear / scroll
# ----------------------------------------------------------------------------

proc write*(rl: RichLogWidget; text: string; color: string = "") =
  ## Append a single log line. If `text` contains embedded `\n` chars,
  ## each segment becomes its own line. When `autoFollow` is on AND the
  ## viewport is currently at the bottom, the new line scrolls into
  ## view; otherwise the visible window is left alone (the user can
  ## press `End` to re-engage auto-follow).
  let stickyBottom = rl.isAtBottom
  if text.len == 0:
    rl.lines.add RichLogLine(text: "", color: color)
  else:
    var start = 0
    for i in 0 .. text.high:
      if text[i] == '\n':
        rl.lines.add RichLogLine(text: text[start ..< i], color: color)
        start = i + 1
    rl.lines.add RichLogLine(text: text[start .. text.high], color: color)
  rl.trimToMax()
  if rl.autoFollow and stickyBottom:
    rl.scrollY = rl.maxScroll
  rl.renderTree()

proc writeLines*(rl: RichLogWidget; texts: openArray[string];
                 color: string = "") =
  ## Append multiple lines in one shot. Slightly more efficient than
  ## calling `write` per line because the tree rebuild fires once.
  let stickyBottom = rl.isAtBottom
  for t in texts:
    rl.lines.add RichLogLine(text: t, color: color)
  rl.trimToMax()
  if rl.autoFollow and stickyBottom:
    rl.scrollY = rl.maxScroll
  rl.renderTree()

proc clear*(rl: RichLogWidget) =
  rl.lines.setLen(0)
  rl.scrollY = 0
  rl.renderTree()

proc scrollEnd*(rl: RichLogWidget) =
  ## Jump to the bottom and re-engage auto-follow. Bound to `End`.
  rl.scrollY = rl.maxScroll
  rl.autoFollow = true
  rl.renderTree()

proc scrollHome*(rl: RichLogWidget) =
  rl.scrollY = 0
  rl.autoFollow = false
  rl.renderTree()

proc pageUp*(rl: RichLogWidget) =
  let step = max(1, rl.viewportHeight - 1)
  rl.scrollY = max(0, rl.scrollY - step)
  rl.autoFollow = false
  rl.renderTree()

proc pageDown*(rl: RichLogWidget) =
  let step = max(1, rl.viewportHeight - 1)
  rl.scrollY = min(rl.maxScroll, rl.scrollY + step)
  if rl.scrollY >= rl.maxScroll:
    rl.autoFollow = true
  rl.renderTree()

proc lineUp*(rl: RichLogWidget) =
  if rl.scrollY > 0:
    dec rl.scrollY
    rl.autoFollow = false
    rl.renderTree()

proc lineDown*(rl: RichLogWidget) =
  if rl.scrollY < rl.maxScroll:
    inc rl.scrollY
    if rl.scrollY >= rl.maxScroll:
      rl.autoFollow = true
    rl.renderTree()

proc id*(rl: RichLogWidget): int {.inline.} = rl.node.id
