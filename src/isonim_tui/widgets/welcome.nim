## widgets/welcome.nim — Tier-3e `Welcome` widget (M21).
##
## Port of `textual/widgets/_welcome.py`. The default empty-state
## screen rendered when an app boots without any user content. It
## paints a centred title, a few lines of body text, and a single
## "OK" affordance at the bottom (purely visual in M21 — wiring the
## affordance to a callback is the caller's job once they install
## focus + key handlers).
##
## Charter §1: every public type is a value object; the widget itself
## is `ref` so callers can replace `body` after construction.

import ../renderer
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

const DefaultWelcomeBody* = @[
  "Welcome to isonim-tui!",
  "",
  "isonim-tui is a Textual-equivalent terminal-UI runtime",
  "for Nim. The widget you are looking at right now is the",
  "default empty-state screen, ready to be replaced with",
  "your own content.",
  "",
  "Press OK to dismiss.",
]

type
  WelcomeWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    title*: string
    body*: seq[string]
    width*: int
    height*: int
    backgroundColor*: string
    color*: string
    actionLabel*: string

# ----------------------------------------------------------------------------
# Forward decl
# ----------------------------------------------------------------------------
proc renderTree*(w: WelcomeWidget)

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

proc centreLine(text: string; width: int): string =
  let textCells = cellWidth(text)
  if textCells >= width: return padOrTruncate(text, width)
  let leftPad = (width - textCells) div 2
  let rightPad = width - textCells - leftPad
  spaces(leftPad) & text & spaces(rightPad)

# ----------------------------------------------------------------------------
# Renderer
# ----------------------------------------------------------------------------

proc renderTree*(w: WelcomeWidget) =
  let r = w.renderer
  clearTreeChildren(r, w.node)
  let glyphs = bordersGlyphs(bsRound)
  let inner = max(2, w.width - 2)

  emitRow(r, w.node, topBorderRow(glyphs, inner), w.color, w.backgroundColor)

  # Title row, then a blank row separator.
  let titleRow = glyphs.left & centreLine(w.title, inner) & glyphs.right
  emitRow(r, w.node, titleRow, w.color, w.backgroundColor)
  let blankRow = glyphs.left & spaces(inner) & glyphs.right
  emitRow(r, w.node, blankRow, w.color, w.backgroundColor)

  # Body lines (clipped to fit the inner area, padded with blanks
  # below until the action label slot).
  let bodySlots = max(0, w.height - 5) # 1 top + 1 title + 1 blank + 1 action + 1 bottom
  for i in 0 ..< bodySlots:
    let line =
      if i < w.body.len: w.body[i]
      else: ""
    let row = glyphs.left & centreLine(line, inner) & glyphs.right
    emitRow(r, w.node, row, w.color, w.backgroundColor)

  # Action affordance — always rendered just above the bottom border.
  let action = "[ " & w.actionLabel & " ]"
  let actionRow = glyphs.left & centreLine(action, inner) & glyphs.right
  emitRow(r, w.node, actionRow, w.color, w.backgroundColor)

  emitRow(r, w.node, bottomBorderRow(glyphs, inner), w.color,
          w.backgroundColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newWelcome*(renderer: TerminalRenderer;
                 title: string = "Welcome";
                 body: openArray[string] = DefaultWelcomeBody;
                 width: int = 60;
                 height: int = 14;
                 actionLabel: string = "OK";
                 backgroundColor: string = "";
                 color: string = ""): WelcomeWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "welcome")
  renderer.setAttribute(node, "class", "welcome")
  var b: seq[string] = @[]
  for line in body: b.add line
  let w = WelcomeWidget(
    renderer: renderer, node: node,
    title: title,
    body: b,
    width: max(20, width),
    height: max(6, height),
    actionLabel: actionLabel,
    backgroundColor: backgroundColor,
    color: color)
  w.renderTree()
  w

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc setTitle*(w: WelcomeWidget; title: string) =
  w.title = title
  w.renderTree()

proc setBody*(w: WelcomeWidget; body: openArray[string]) =
  var b: seq[string] = @[]
  for line in body: b.add line
  w.body = b
  w.renderTree()

proc setActionLabel*(w: WelcomeWidget; label: string) =
  w.actionLabel = label
  w.renderTree()

proc id*(w: WelcomeWidget): int {.inline.} = w.node.id
