## widgets/container.nim — Tier-1a `Container` widget.
##
## Port of the `Container` behaviour from `textual/widget.py`. A
## `Container` is the parent of arbitrary child widgets. It supports
## an optional border, an optional viewport-bounded scroll region, and
## (later, in M14) layout-mode switching between vertical / horizontal
## / grid.
##
## *Border + scrolling*: same machinery as `Static`, factored through
## the `borders` module. The container's children are arbitrary
## widget nodes (or raw `TerminalNode`s); the widget builds a
## bordered "frame" around the user content by inserting top / bottom
## border rows and prefix-/suffix-stamping the per-child rows with the
## vertical-edge glyph.
##
## Charter §1: value types in the public API (the children list is
## `seq[TerminalNode]` so adding/removing is a value-copy update); the
## widget itself is a `ref` so callers can mutate its state.

import ../renderer
import ../events
import ../css/properties
import ./borders

type
  ContainerLayout* = enum
    clVertical
    clHorizontal
    clGrid

  ContainerWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    childWidgets*: seq[TerminalNode]   ## User content rows.
    border*: BorderStyle
    borderColor*: string
    layout*: ContainerLayout
    width*: int                        ## Inner width in cells.
    viewportHeight*: int               ## How many rows the viewport
                                       ## shows. Total content can
                                       ## exceed this; the rest is
                                       ## reachable by scrolling.
    scrollY*: int
    scrollable*: bool

# Forward declarations so the keydown closure installed in
# `newContainer` can reference `pageDown` / `pageUp` ahead of their
# definitions further down. Closures resolve identifiers lazily so
# only the type needs to be in scope at the closure-construction
# call-site.
proc pageDown*(c: ContainerWidget)
proc pageUp*(c: ContainerWidget)
proc renderTree*(c: ContainerWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitTextRow(r: TerminalRenderer; parent: TerminalNode;
                 text: string; color: string) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc childText(child: TerminalNode): string =
  ## Extract the visible text of `child`. Falls back to `textContent`
  ## (concatenation across sub-text nodes) so any widget that emits
  ## one text payload per child contributes its content. This keeps
  ## the M11 viewport renderer simple — every Tier-1a child whose own
  ## tree boils down to one logical row works without further
  ## annotation.
  textContent(child)

proc renderTree*(c: ContainerWidget) =
  let r = c.renderer
  clearTreeChildren(r, c.node)
  let glyphs = bordersGlyphs(c.border)
  let useBorder = c.border != bsNone
  if useBorder:
    emitTextRow(r, c.node, topBorderRow(glyphs, c.width), c.borderColor)
  let visible = max(0, min(c.childWidgets.len - c.scrollY, c.viewportHeight))
  for i in 0 ..< visible:
    let child = c.childWidgets[c.scrollY + i]
    let body = padOrTruncate(childText(child), c.width)
    if useBorder:
      emitTextRow(r, c.node,
                  glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")
  # Pad to viewport.
  for _ in visible ..< c.viewportHeight:
    let body = spaces(c.width)
    if useBorder:
      emitTextRow(r, c.node, glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")
  if useBorder:
    emitTextRow(r, c.node, bottomBorderRow(glyphs, c.width), c.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newContainer*(renderer: TerminalRenderer;
                   width, viewportHeight: int;
                   border: BorderStyle = bsNone;
                   borderColor: string = "";
                   layout: ContainerLayout = clVertical;
                   scrollable: bool = false): ContainerWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "container")
  if scrollable:
    renderer.setAttribute(node, "data-scrollable", "true")
  let c = ContainerWidget(
    renderer: renderer, node: node,
    childWidgets: @[],
    border: border, borderColor: borderColor,
    layout: layout, width: width,
    viewportHeight: viewportHeight,
    scrollY: 0, scrollable: scrollable)
  c.renderTree()
  if scrollable:
    renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
      if ev.kind != ekKey: return
      case ev.key.key
      of "pagedown", "pageDown", "PageDown": c.pageDown()
      of "pageup", "pageUp", "PageUp": c.pageUp()
      else: discard)
  c

proc append*(c: ContainerWidget; child: TerminalNode) =
  ## Add a child widget node. Triggers a re-render.
  c.childWidgets.add child
  c.renderTree()

proc appendAll*(c: ContainerWidget; children: openArray[TerminalNode]) =
  ## Bulk add — only one re-render at the end.
  for child in children:
    c.childWidgets.add child
  c.renderTree()

# ----------------------------------------------------------------------------
# Scrolling
# ----------------------------------------------------------------------------

proc pageDown*(c: ContainerWidget) =
  if not c.scrollable: return
  let step = max(1, c.viewportHeight - 1)
  let maxOffset = max(0, c.childWidgets.len - c.viewportHeight)
  c.scrollY = min(c.scrollY + step, maxOffset)
  c.renderTree()

proc pageUp*(c: ContainerWidget) =
  if not c.scrollable: return
  let step = max(1, c.viewportHeight - 1)
  c.scrollY = max(0, c.scrollY - step)
  c.renderTree()

proc scrollTo*(c: ContainerWidget; line: int) =
  let maxOffset = max(0, c.childWidgets.len - c.viewportHeight)
  c.scrollY = max(0, min(line, maxOffset))
  c.renderTree()

proc id*(c: ContainerWidget): int {.inline.} = c.node.id

proc setLayout*(c: ContainerWidget; layout: ContainerLayout) =
  ## Switch the container's layout mode. M11 only renders vertical
  ## stacks; horizontal / grid land in M14 with the layout cascade
  ## integration. The setter is here so callers can declare intent
  ## today without having to refactor when the renderer catches up.
  c.layout = layout
  case layout
  of clVertical: c.renderer.setStyle(c.node, "layout", "vertical")
  of clHorizontal: c.renderer.setStyle(c.node, "layout", "horizontal")
  of clGrid: c.renderer.setStyle(c.node, "layout", "grid")
