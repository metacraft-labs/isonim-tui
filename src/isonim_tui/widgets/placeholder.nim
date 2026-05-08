## widgets/placeholder.nim — Tier-1a `Placeholder` widget.
##
## Port of `textual/widgets/placeholder.py`. A `Placeholder` is a
## named coloured box used during layout debugging — it makes a
## widget's footprint visible without requiring real content.
##
## *Deterministic colour*: the same `name` always renders with the
## same background colour, so a layout-debug screenshot taken after
## an unrelated change won't churn just because palette ordering
## drifted. The colour pool is the 8 ANSI hues; the index is `hash(
## name) mod 8`.
##
## Charter §1: value types throughout. The placeholder paints itself
## through the same border / row machinery as `Static`.

import std/[hashes]

import ../renderer
import ../css/properties
import ./borders

# Deterministic colour pool — six legible ANSI hues.
const placeholderColors* = [
  "blue", "green", "magenta", "cyan", "yellow", "red"
]

proc colorForName*(name: string): string =
  ## Stable colour pick for a placeholder name. Uses Nim's `Hash` on
  ## the string + modulo so the choice is identical across runs.
  if name.len == 0:
    return placeholderColors[0]
  let h = hash(name)
  let idx = (abs(h.int) mod placeholderColors.len)
  placeholderColors[idx]

type
  PlaceholderWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    name*: string
    width*: int                     ## Inner width.
    height*: int                    ## Inner height (in rows).
    color*: string                  ## Resolved deterministic colour.

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitColoredRow(r: TerminalRenderer; parent: TerminalNode;
                    text: string; color: string) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderTree*(p: PlaceholderWidget) =
  let r = p.renderer
  clearTreeChildren(r, p.node)
  let glyphs = bordersGlyphs(bsSolid)
  emitColoredRow(r, p.node, topBorderRow(glyphs, p.width), p.color)
  # Centre the name vertically. With small heights we just stamp it on
  # the first inner row.
  let nameLine =
    if p.width >= p.name.len:
      let pad = (p.width - p.name.len) div 2
      let leftPad = spaces(pad)
      let rightPad = spaces(p.width - p.name.len - pad)
      glyphs.left & leftPad & p.name & rightPad & glyphs.right
    else:
      glyphs.left & padOrTruncate(p.name, p.width) & glyphs.right
  let nameRowIdx = max(0, p.height div 2)
  for row in 0 ..< p.height:
    if row == nameRowIdx:
      emitColoredRow(r, p.node, nameLine, p.color)
    else:
      emitColoredRow(r, p.node,
                     glyphs.left & spaces(p.width) & glyphs.right, p.color)
  emitColoredRow(r, p.node, bottomBorderRow(glyphs, p.width), p.color)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newPlaceholder*(renderer: TerminalRenderer; name: string;
                     width: int = 20; height: int = 5): PlaceholderWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "placeholder")
  renderer.setAttribute(node, "data-placeholder-name", name)
  let color = colorForName(name)
  renderer.setStyle(node, "border-color", color)
  let p = PlaceholderWidget(
    renderer: renderer, node: node,
    name: name, width: width, height: height,
    color: color)
  p.renderTree()
  p

proc setName*(p: PlaceholderWidget; name: string) =
  p.name = name
  p.color = colorForName(name)
  p.renderer.setAttribute(p.node, "data-placeholder-name", name)
  p.renderer.setStyle(p.node, "border-color", p.color)
  p.renderTree()

proc id*(p: PlaceholderWidget): int {.inline.} = p.node.id
