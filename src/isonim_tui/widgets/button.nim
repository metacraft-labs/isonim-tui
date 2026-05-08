## widgets/button.nim — Tier-1b `Button` widget.
##
## Port of `textual/widgets/_button.py` + `textual/widgets/button.py`.
## A button is a labelled, focusable widget that fires a `click`
## event when activated. Activation routes are:
##   * Mouse click on the button's cell rectangle
##   * `Enter` while focused
##   * `Space` while focused
##
## The visual treatment is a rounded-corner box with the label
## centred horizontally. Default + `:focus` + `:hover` + `:disabled`
## styling drops out of the M5 cascade — the widget sets the
## necessary attributes (`data-focusable`, `disabled`, etc.) and the
## CSS engine takes care of the rest.
##
## Charter §1: every public type is a value object; the widget handle
## itself is a `ref` so callers can mutate `setLabel` after
## construction.

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public widget type
# ----------------------------------------------------------------------------

type
  ButtonVariant* = enum
    ## Variant taxonomy mirrors Textual: default / primary / success /
    ## warning / error. The variant becomes a class on the rendered
    ## node so app stylesheets can target each variant.
    bvDefault
    bvPrimary
    bvSuccess
    bvWarning
    bvError

  ButtonWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    label*: string
    variant*: ButtonVariant
    width*: int                     ## Inner width in cells.
    border*: BorderStyle
    borderColor*: string
    disabled*: bool
    onClick*: proc()                ## Optional convenience callback.

# Forward declaration so `newButton`'s key handler can reference
# `activate` ahead of its definition.
proc activate*(b: ButtonWidget)
proc renderTree*(b: ButtonWidget)

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

proc centeredLabel(label: string; width: int): string =
  ## Cell-aware horizontal centring. Truncates with cell precision
  ## when the label is wider than the inner width.
  if width <= 0: return ""
  let truncated = padOrTruncate(label, width)
  # padOrTruncate left-aligns; centre by computing pads explicitly.
  let labelCells = cellWidth(label)
  if labelCells >= width:
    return truncated
  let leftPad = (width - labelCells) div 2
  let rightPad = width - labelCells - leftPad
  spaces(leftPad) & label & spaces(rightPad)

proc renderTree*(b: ButtonWidget) =
  let r = b.renderer
  clearTreeChildren(r, b.node)
  let glyphs = bordersGlyphs(b.border)
  let useBorder = b.border != bsNone
  if useBorder:
    emitRow(r, b.node, topBorderRow(glyphs, b.width), b.borderColor)
  let body = centeredLabel(b.label, b.width)
  if useBorder:
    emitRow(r, b.node, glyphs.left & body & glyphs.right, b.borderColor)
  else:
    emitRow(r, b.node, body, b.borderColor)
  if useBorder:
    emitRow(r, b.node, bottomBorderRow(glyphs, b.width), b.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc variantClass(v: ButtonVariant): string =
  case v
  of bvDefault: "default"
  of bvPrimary: "primary"
  of bvSuccess: "success"
  of bvWarning: "warning"
  of bvError:   "error"

proc newButton*(renderer: TerminalRenderer;
                label: string;
                width: int = 0;
                variant: ButtonVariant = bvDefault;
                border: BorderStyle = bsRound;
                borderColor: string = "";
                disabled: bool = false;
                onClick: proc() = nil): ButtonWidget =
  ## Construct a button. `width` of 0 auto-sizes to `label.len + 4`
  ## (two cells of padding on each side, mirrors Textual's default).
  let actualWidth =
    if width > 0: width
    else: max(cellWidth(label) + 4, 4)
  let node = renderer.createElement("button")
  renderer.setAttribute(node, "data-widget", "button")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "data-variant", variantClass(variant))
  renderer.setAttribute(node, "class", "button " & variantClass(variant))
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  let b = ButtonWidget(
    renderer: renderer, node: node,
    label: label, variant: variant,
    width: actualWidth,
    border: border, borderColor: borderColor,
    disabled: disabled, onClick: onClick)
  b.renderTree()

  # Activation via Enter / Space when focused. Mouse click handlers
  # are wired by the caller via `addEventListener(node, "click", …)`
  # — we still install one for the convenience callback.
  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    if b.disabled: return
    let name = ev.key.key
    if name == "enter" or name == "return" or name == "space" or
       (ev.key.kind == kkChar and ev.key.rune == uint32(' '.ord)):
      b.activate())
  renderer.addEventListener(node, "click", proc(ev: TerminalEvent) =
    if b.disabled: return
    if b.onClick != nil: b.onClick())
  b

# ----------------------------------------------------------------------------
# Activation
# ----------------------------------------------------------------------------

proc activate*(b: ButtonWidget) =
  ## Fire the `click` event on the underlying node. Called from the
  ## key handler (Enter / Space) and exposed publicly so test code can
  ## activate without going through the pilot.
  if b.disabled: return
  fireEvent(b.node, "click")

# ----------------------------------------------------------------------------
# Mutators
# ----------------------------------------------------------------------------

proc setLabel*(b: ButtonWidget; label: string) =
  b.label = label
  b.renderTree()

proc setDisabled*(b: ButtonWidget; disabled: bool) =
  b.disabled = disabled
  if disabled:
    b.renderer.setAttribute(b.node, "disabled", "true")
    b.renderer.setAttribute(b.node, "data-focusable", "false")
  else:
    b.renderer.removeAttribute(b.node, "disabled")
    b.renderer.setAttribute(b.node, "data-focusable", "true")

proc id*(b: ButtonWidget): int {.inline.} = b.node.id
