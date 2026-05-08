## widgets/loading_indicator.nim — Tier-2 `LoadingIndicator` widget (M14).
##
## Port of `textual/widgets/loading_indicator.py` (~93 LOC). A simple
## animated spinner that rotates through a sequence of glyphs to
## signal "work in progress". The cycle advances on every M7 animator
## tick (default 16.7 ms / frame at 60 Hz). Tests can call
## `tickFrame()` directly to advance without the animator.
##
## Charter §1: the widget handle is `ref` (mutates state); every
## value flowing through the public API is a value object.

import ../renderer

const SpinnerFrames = @[
  "\xE2\xA0\x8B",   # ⠋
  "\xE2\xA0\x99",   # ⠙
  "\xE2\xA0\xB9",   # ⠹
  "\xE2\xA0\xB8",   # ⠸
  "\xE2\xA0\xBC",   # ⠼
  "\xE2\xA0\xB4",   # ⠴
  "\xE2\xA0\xA6",   # ⠦
  "\xE2\xA0\xA7",   # ⠧
  "\xE2\xA0\x87",   # ⠇
  "\xE2\xA0\x8F",   # ⠏
]

type
  LoadingIndicatorWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    label*: string                 ## Optional message right of the spinner.
    color*: string
    frame*: int                    ## Active frame index in `SpinnerFrames`.
    visible*: bool                 ## When false, renders as blanks
                                   ## (caller hides without unmounting).

proc renderTree*(li: LoadingIndicatorWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc currentGlyph*(li: LoadingIndicatorWidget): string =
  if not li.visible: return " "
  let idx = li.frame mod SpinnerFrames.len
  SpinnerFrames[idx]

proc renderTree*(li: LoadingIndicatorWidget) =
  let r = li.renderer
  clearTreeChildren(r, li.node)
  let row = r.createElement("div")
  if li.color.len > 0:
    r.setStyle(row, "color", li.color)
  let glyph = currentGlyph(li)
  let txt =
    if li.label.len > 0: glyph & " " & li.label
    else: glyph
  r.appendChild(row, r.createTextNode(txt))
  r.appendChild(li.node, row)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newLoadingIndicator*(renderer: TerminalRenderer;
                           label: string = "";
                           color: string = ""): LoadingIndicatorWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "loading-indicator")
  renderer.setAttribute(node, "class", "loading-indicator")
  let li = LoadingIndicatorWidget(
    renderer: renderer, node: node,
    label: label, color: color,
    frame: 0, visible: true)
  li.renderTree()
  li

# ----------------------------------------------------------------------------
# Frame advance
# ----------------------------------------------------------------------------

proc tickFrame*(li: LoadingIndicatorWidget) =
  ## Advance the spinner one frame. Tests call this directly; production
  ## wires it to the M7 animator's frame ticker.
  li.frame = (li.frame + 1) mod SpinnerFrames.len
  li.renderTree()

proc setLabel*(li: LoadingIndicatorWidget; label: string) =
  li.label = label
  li.renderTree()

proc setVisible*(li: LoadingIndicatorWidget; visible: bool) =
  li.visible = visible
  li.renderTree()

proc id*(li: LoadingIndicatorWidget): int {.inline.} = li.node.id
