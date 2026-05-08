## widgets/checkbox.nim — Tier-1b `Checkbox` widget.
##
## Port of `textual/widgets/_checkbox.py`. A checkbox is a labelled
## boolean toggle visually distinct from a `Switch`: it uses the
## `[x]` / `[ ]` glyph pair followed by a label. Activation via
## `Space` (or mouse click).
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers mutate state directly.

import ../renderer
import ../events

type
  CheckboxWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    label*: string
    value*: bool
    disabled*: bool
    onChange*: proc(newValue: bool)
    color*: string

proc toggle*(c: CheckboxWidget)
proc renderTree*(c: CheckboxWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc checkboxGlyph(value: bool): string =
  ## The visible glyph. `[x]` for checked, `[ ]` for unchecked. Pure
  ## ASCII so it survives any terminal width quirks.
  if value: "[x]"
  else: "[ ]"

proc renderTree*(c: CheckboxWidget) =
  let r = c.renderer
  clearTreeChildren(r, c.node)
  let row = r.createElement("div")
  if c.color.len > 0:
    r.setStyle(row, "color", c.color)
  let text =
    if c.label.len > 0: checkboxGlyph(c.value) & " " & c.label
    else: checkboxGlyph(c.value)
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(c.node, row)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newCheckbox*(renderer: TerminalRenderer;
                  label: string = "";
                  value: bool = false;
                  disabled: bool = false;
                  color: string = "";
                  onChange: proc(newValue: bool) = nil): CheckboxWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "checkbox")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "checkbox")
  if value:
    renderer.setAttribute(node, "data-value", "on")
  else:
    renderer.setAttribute(node, "data-value", "off")
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  let c = CheckboxWidget(
    renderer: renderer, node: node,
    label: label, value: value, disabled: disabled,
    onChange: onChange, color: color)
  c.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    if c.disabled: return
    let name = ev.key.key
    if name == "space" or name == "enter" or name == "return" or
       (ev.key.kind == kkChar and ev.key.rune == uint32(' '.ord)):
      c.toggle())
  renderer.addEventListener(node, "click", proc(ev: TerminalEvent) =
    if c.disabled: return
    c.toggle())
  c

# ----------------------------------------------------------------------------
# Mutators
# ----------------------------------------------------------------------------

proc setValue*(c: CheckboxWidget; value: bool) =
  if c.value == value: return
  c.value = value
  c.renderer.setAttribute(c.node, "data-value",
                          (if value: "on" else: "off"))
  c.renderTree()
  if c.onChange != nil: c.onChange(value)

proc toggle*(c: CheckboxWidget) =
  if c.disabled: return
  c.setValue(not c.value)

proc setLabel*(c: CheckboxWidget; label: string) =
  c.label = label
  c.renderTree()

proc setDisabled*(c: CheckboxWidget; disabled: bool) =
  c.disabled = disabled
  if disabled:
    c.renderer.setAttribute(c.node, "disabled", "true")
    c.renderer.setAttribute(c.node, "data-focusable", "false")
  else:
    c.renderer.removeAttribute(c.node, "disabled")
    c.renderer.setAttribute(c.node, "data-focusable", "true")

proc id*(c: CheckboxWidget): int {.inline.} = c.node.id
