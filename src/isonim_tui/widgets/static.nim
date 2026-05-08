## widgets/static.nim — Tier-1a `Static` widget.
##
## Port of `textual/widgets/static.py`. A `Static` is a bordered or
## borderless content container with optional scrolling. It is the
## simplest layout-and-text primitive every interactive widget in M12+
## sits inside.
##
## *Charter §1*: every value flowing through the public API is a value
## object. The `Static` value carries the renderer-mounted node and the
## widget's mutable state in a single ref-typed wrapper so callers can
## pass the widget around as a handle.
##
## *Borders*: M11 introduces real border drawing. Borders are emitted
## as text rows in the underlying tree (top / middle / bottom) so the
## M8 compositor flattens them into the layered cell stream without
## any compositor changes. The border style is one of
## `properties.BorderStyle`; the colour is honoured via the standard
## inline style table.
##
## *Scrolling*: when the content has more lines than the configured
## `viewport` height, `pageUp` / `pageDown` advance the visible window
## by `viewport - 1` lines (mirrors Textual's "keep one anchor row").
## Scrolling rebuilds the visible children; the M8 strip cache absorbs
## the repeat work for unchanged rows.

import std/[strutils]

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public widget value type
# ----------------------------------------------------------------------------

type
  StaticWidget* = ref object
    ## The widget handle. Holds a back-reference to the renderer that
    ## built it and the root node it mounted, plus the mutable state
    ## (current content lines, current scroll offset, current border
    ## style + colour).
    renderer*: TerminalRenderer
    node*: TerminalNode             ## The container node in the tree.
    contentLines*: seq[string]      ## One entry per logical line.
    border*: BorderStyle
    borderColor*: string            ## Empty string = no explicit colour.
    width*: int                     ## Inner cell width (excludes borders).
    height*: int                    ## Inner viewport height in rows.
    scrollY*: int                   ## Index of the first visible line.
    scrollable*: bool

# Forward declarations so the keydown handler installed in
# `newStatic` can reference `pageDown` / `pageUp` before they're
# defined further down. Nim resolves these lazily inside closures, so
# only the type needs to exist before `addEventListener` sees them.
proc pageDown*(s: StaticWidget)
proc pageUp*(s: StaticWidget)
proc renderTree*(s: StaticWidget)

# ----------------------------------------------------------------------------
# Tree builders
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  ## Drop the existing children so we can rebuild the visible window.
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "") =
  ## Emit a single visible row as a child box wrapping a single text
  ## node. The compositor's flatten-to-rows pass turns each such box
  ## into exactly one row of cells (because all children are tnkText).
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderTree*(s: StaticWidget) =
  ## (Re)build the visible children of `s.node` from the current
  ## content + scroll offset. Idempotent; safe to call after every
  ## state mutation.
  let r = s.renderer
  clearTreeChildren(r, s.node)
  let glyphs = bordersGlyphs(s.border)
  let useBorder = s.border != bsNone
  if useBorder:
    emitRow(r, s.node, topBorderRow(glyphs, s.width), s.borderColor)
  let visible = max(0, min(s.contentLines.len - s.scrollY, s.height))
  for i in 0 ..< visible:
    let line = s.contentLines[s.scrollY + i]
    let body = padOrTruncate(line, s.width)
    if useBorder:
      emitRow(r, s.node, glyphs.left & body & glyphs.right, s.borderColor)
    else:
      emitRow(r, s.node, body)
  # Pad with blank rows so the widget keeps its declared height.
  for _ in visible ..< s.height:
    let body = spaces(s.width)
    if useBorder:
      emitRow(r, s.node, glyphs.left & body & glyphs.right, s.borderColor)
    else:
      emitRow(r, s.node, body)
  if useBorder:
    emitRow(r, s.node, bottomBorderRow(glyphs, s.width), s.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newStatic*(renderer: TerminalRenderer; content: string;
                width, height: int;
                border: BorderStyle = bsNone;
                borderColor: string = "";
                scrollable: bool = false): StaticWidget =
  ## Construct a fresh `Static` widget. `content` may contain embedded
  ## `\n` separators; each one starts a new logical line. `width` and
  ## `height` are the inner content dimensions (the border, when set,
  ## adds 1 cell on each axis).
  ##
  ## Returns the widget handle. Mount it into a parent with
  ## `parent.appendStatic(widget)` (or pass it through the `appendChild`
  ## API directly via `widget.node`).
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "static")
  if border != bsNone:
    renderer.setStyle(node, "border", $ord(border))
  if borderColor.len > 0:
    renderer.setStyle(node, "border-color", borderColor)
  let lines =
    if content.len == 0: @[""]
    else: content.split('\n')
  let s = StaticWidget(
    renderer: renderer, node: node,
    contentLines: lines,
    border: border, borderColor: borderColor,
    width: width, height: height,
    scrollY: 0, scrollable: scrollable)
  s.renderTree()
  if scrollable:
    # Wire up keyboard scrolling. Each PgUp / PgDn advances by one
    # viewport-page (with a one-row anchor).
    renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
      if ev.kind != ekKey: return
      case ev.key.key
      of "pagedown", "pageDown", "PageDown":
        s.pageDown()
      of "pageup", "pageUp", "PageUp":
        s.pageUp()
      else: discard)
  s

proc setContent*(s: StaticWidget; content: string) =
  ## Replace the content. Resets the scroll position.
  s.contentLines =
    if content.len == 0: @[""]
    else: content.split('\n')
  s.scrollY = 0
  s.renderTree()

# ----------------------------------------------------------------------------
# Scrolling
# ----------------------------------------------------------------------------

proc pageDown*(s: StaticWidget) =
  ## Advance one viewport page (height - 1 lines). Clamps to
  ## `len(content) - height` so the last row stays visible.
  if not s.scrollable: return
  let step = max(1, s.height - 1)
  let maxOffset = max(0, s.contentLines.len - s.height)
  s.scrollY = min(s.scrollY + step, maxOffset)
  s.renderTree()

proc pageUp*(s: StaticWidget) =
  ## Reverse of `pageDown`. Clamps to 0.
  if not s.scrollable: return
  let step = max(1, s.height - 1)
  s.scrollY = max(0, s.scrollY - step)
  s.renderTree()

proc scrollTo*(s: StaticWidget; line: int) =
  ## Set the scroll offset directly, clamped.
  let maxOffset = max(0, s.contentLines.len - s.height)
  s.scrollY = max(0, min(line, maxOffset))
  s.renderTree()

# ----------------------------------------------------------------------------
# Mount helpers
# ----------------------------------------------------------------------------

proc appendStatic*(parent: TerminalNode; renderer: TerminalRenderer;
                   widget: StaticWidget) =
  ## Convenience: mount the widget under `parent`.
  renderer.appendChild(parent, widget.node)

# Re-export the underlying node so callers can do `widget.node.id` or
# pass it directly to `r.appendChild(parent, widget.node)`.
proc id*(s: StaticWidget): int {.inline.} = s.node.id
