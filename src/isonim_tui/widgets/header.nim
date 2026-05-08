## widgets/header.nim — Tier-3e `Header` widget (M21).
##
## Port of `textual/widgets/_header.py`. App chrome that docks at the
## top of the screen. Carries a left-edge icon, a centred title /
## subtitle, and (optionally) a right-edge clock placeholder. The
## widget is a single line by default; the `tall` flag expands to
## three lines (icon + title + subtitle).
##
## A `Header` is non-interactive in the M21 surface — clicking the icon
## doesn't toggle the command palette yet (palette wiring is M16's
## separate widget). The widget exists primarily as the dock-able
## chrome the M11–M21 widget set composes against.
##
## Charter §1: every public type is a value object; the widget itself
## is `ref` so callers can mutate `setTitle`, `setSubtitle` after
## construction.

import ../renderer
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  HeaderWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    icon*: string             ## Single-glyph icon shown at the left.
    title*: string
    subtitle*: string
    clockText*: string        ## When non-empty, shown right-justified.
    width*: int               ## Total width in cells.
    tall*: bool               ## When true, render across three rows.
    backgroundColor*: string  ## Inline background colour.
    color*: string            ## Inline foreground colour.

# ----------------------------------------------------------------------------
# Forward decl
# ----------------------------------------------------------------------------
proc renderTree*(h: HeaderWidget)

# ----------------------------------------------------------------------------
# Tree builder helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; fg: string = ""; bg: string = "") =
  let box = r.createElement("div")
  if fg.len > 0: r.setStyle(box, "color", fg)
  if bg.len > 0: r.setStyle(box, "background-color", bg)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderRow(width: int; left, centre, right: string): string =
  ## Compose a single row split into three regions: left-aligned
  ## `left`, centred `centre`, right-aligned `right`. When the regions
  ## together exceed the width, the centre is truncated.
  if width <= 0: return ""
  let leftLen = min(left.len, width)
  let leftPart = left.substr(0, leftLen - 1)
  let rightLen = min(right.len, max(0, width - leftLen))
  let rightPart = right.substr(0, rightLen - 1)
  let middleSpace = max(0, width - leftLen - rightLen)
  let centreTrunc =
    if centre.len > middleSpace: centre.substr(0, max(0, middleSpace - 1))
    else: centre
  let leftPad = (middleSpace - centreTrunc.len) div 2
  let rightPad = middleSpace - centreTrunc.len - leftPad
  result = leftPart & spaces(leftPad) & centreTrunc & spaces(rightPad) &
           rightPart

# ----------------------------------------------------------------------------
# Renderer
# ----------------------------------------------------------------------------

proc renderTree*(h: HeaderWidget) =
  let r = h.renderer
  clearTreeChildren(r, h.node)
  let leftZone =
    if h.icon.len > 0: " " & h.icon & " "
    else: "   "
  let rightZone =
    if h.clockText.len > 0: " " & h.clockText & " "
    else: ""
  if h.tall:
    let blank = renderRow(h.width, leftZone, "", rightZone)
    let titleRow = renderRow(h.width, leftZone, h.title, rightZone)
    let subtitleRow = renderRow(h.width, "", h.subtitle, "")
    emitRow(r, h.node, blank, h.color, h.backgroundColor)
    emitRow(r, h.node, titleRow, h.color, h.backgroundColor)
    emitRow(r, h.node, subtitleRow, h.color, h.backgroundColor)
  else:
    let centre =
      if h.subtitle.len > 0: h.title & " — " & h.subtitle
      else: h.title
    let row = renderRow(h.width, leftZone, centre, rightZone)
    emitRow(r, h.node, row, h.color, h.backgroundColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newHeader*(renderer: TerminalRenderer;
                title: string = "";
                subtitle: string = "";
                icon: string = "\xE2\xAD\x90"; # ⭐ default per Textual ⭘
                width: int = 80;
                tall: bool = false;
                backgroundColor: string = "blue";
                color: string = "white"): HeaderWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "header")
  renderer.setAttribute(node, "class", "header")
  let h = HeaderWidget(
    renderer: renderer, node: node,
    icon: icon, title: title, subtitle: subtitle,
    clockText: "",
    width: max(8, width),
    tall: tall,
    backgroundColor: backgroundColor, color: color)
  h.renderTree()
  h

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc setTitle*(h: HeaderWidget; title: string) =
  h.title = title
  h.renderTree()

proc setSubtitle*(h: HeaderWidget; subtitle: string) =
  h.subtitle = subtitle
  h.renderTree()

proc setIcon*(h: HeaderWidget; icon: string) =
  h.icon = icon
  h.renderTree()

proc setClock*(h: HeaderWidget; clockText: string) =
  h.clockText = clockText
  h.renderTree()

proc setTall*(h: HeaderWidget; tall: bool) =
  h.tall = tall
  h.renderTree()

proc id*(h: HeaderWidget): int {.inline.} = h.node.id
