## widgets/switch.nim — Tier-1b `Switch` widget.
##
## Port of `textual/widgets/switch.py`. A switch is a focusable
## boolean toggle. Activation is via `Space` (or mouse click). The
## visual treatment is a `[●·]` / `[·●]` slider — three runes total,
## with the dot moving between left and right based on `value`.
##
## Reactive integration: the widget exposes a `value: bool` field
## that callers read. Apps that want signal-driven binding wrap a
## reactive signal around `setValue` / a `(b)=> sig.set(b)` callback.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers mutate state directly.

import ../renderer
import ../events

type
  SwitchWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    value*: bool
    disabled*: bool
    onChange*: proc(newValue: bool)
    color*: string

# Forward declaration so the keydown closure resolves.
proc toggle*(s: SwitchWidget)
proc renderTree*(s: SwitchWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc switchGlyphs(value: bool): string =
  ## The visible representation. `[●·]` for off, `[·●]` for on. Total
  ## width is 4 cells: left bracket + slider + slider + right bracket.
  if value: "[·●]"
  else: "[●·]"

proc renderTree*(s: SwitchWidget) =
  let r = s.renderer
  clearTreeChildren(r, s.node)
  let row = r.createElement("div")
  if s.color.len > 0:
    r.setStyle(row, "color", s.color)
  r.appendChild(row, r.createTextNode(switchGlyphs(s.value)))
  r.appendChild(s.node, row)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newSwitch*(renderer: TerminalRenderer;
                value: bool = false;
                disabled: bool = false;
                color: string = "";
                onChange: proc(newValue: bool) = nil): SwitchWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "switch")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "switch")
  if value:
    renderer.setAttribute(node, "data-value", "on")
  else:
    renderer.setAttribute(node, "data-value", "off")
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  let s = SwitchWidget(
    renderer: renderer, node: node,
    value: value, disabled: disabled,
    onChange: onChange, color: color)
  s.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    if s.disabled: return
    let name = ev.key.key
    if name == "space" or name == "enter" or name == "return" or
       (ev.key.kind == kkChar and ev.key.rune == uint32(' '.ord)):
      s.toggle())
  renderer.addEventListener(node, "click", proc(ev: TerminalEvent) =
    if s.disabled: return
    s.toggle())
  s

# ----------------------------------------------------------------------------
# Mutators
# ----------------------------------------------------------------------------

proc setValue*(s: SwitchWidget; value: bool) =
  if s.value == value: return
  s.value = value
  s.renderer.setAttribute(s.node, "data-value",
                          (if value: "on" else: "off"))
  s.renderTree()
  if s.onChange != nil: s.onChange(value)

proc toggle*(s: SwitchWidget) =
  if s.disabled: return
  s.setValue(not s.value)

proc setDisabled*(s: SwitchWidget; disabled: bool) =
  s.disabled = disabled
  if disabled:
    s.renderer.setAttribute(s.node, "disabled", "true")
    s.renderer.setAttribute(s.node, "data-focusable", "false")
  else:
    s.renderer.removeAttribute(s.node, "disabled")
    s.renderer.setAttribute(s.node, "data-focusable", "true")

proc id*(s: SwitchWidget): int {.inline.} = s.node.id
