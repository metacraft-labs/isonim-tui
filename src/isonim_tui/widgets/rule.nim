## widgets/rule.nim — Tier-1a `Rule` widget.
##
## Port of `textual/widgets/rule.py`. A `Rule` is a separator line
## drawn in box-drawing characters. Two orientations: `roHorizontal`
## (a single row stretching `width` cells) and `roVertical` (a single
## column stretching `height` rows).
##
## The line style follows the same `BorderStyle` taxonomy as the
## bordered widgets — `solid`, `heavy`, `double`, `dashed`, `ascii`.
## The matching glyph is drawn `width` (or `height`) times.
##
## Charter §1: value types throughout.

import ../renderer
import ../css/properties
import ./borders

type
  RuleOrientation* = enum
    roHorizontal
    roVertical

  RuleWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    orientation*: RuleOrientation
    width*: int                  ## Used for horizontal rules.
    height*: int                 ## Used for vertical rules.
    style*: BorderStyle
    color*: string

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc renderTree*(rule: RuleWidget) =
  let r = rule.renderer
  clearTreeChildren(r, rule.node)
  let glyphs = bordersGlyphs(rule.style)
  case rule.orientation
  of roHorizontal:
    var line = ""
    for _ in 0 ..< rule.width:
      line.add glyphs.horizontal
    let box = r.createElement("div")
    if rule.color.len > 0:
      r.setStyle(box, "color", rule.color)
    r.appendChild(box, r.createTextNode(line))
    r.appendChild(rule.node, box)
  of roVertical:
    for _ in 0 ..< rule.height:
      let row = r.createElement("div")
      if rule.color.len > 0:
        r.setStyle(row, "color", rule.color)
      r.appendChild(row, r.createTextNode(glyphs.vertical))
      r.appendChild(rule.node, row)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newRule*(renderer: TerminalRenderer;
              orientation: RuleOrientation = roHorizontal;
              width: int = 0; height: int = 1;
              style: BorderStyle = bsSolid;
              color: string = ""): RuleWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "rule")
  let r = RuleWidget(
    renderer: renderer, node: node,
    orientation: orientation,
    width: width, height: height,
    style: style, color: color)
  r.renderTree()
  r

proc setStyle*(rule: RuleWidget; style: BorderStyle) =
  rule.style = style
  rule.renderTree()

proc setColor*(rule: RuleWidget; color: string) =
  rule.color = color
  rule.renderTree()

proc id*(rule: RuleWidget): int {.inline.} = rule.node.id
