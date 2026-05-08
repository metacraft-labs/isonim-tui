## widgets/radio_button.nim — Tier-1b `RadioButton` widget.
##
## Port of `textual/widgets/radio_button.py`. A radio button is a
## focusable selector that participates in an exclusive-selection
## group (its `RadioSet`). Visually it uses the `(•)` / `( )` glyph
## pair, mirroring `Checkbox`'s `[x]` / `[ ]`.
##
## Activation via `Space` (or mouse click) flips the button's state
## to selected; the parent `RadioSet` (when present) deselects every
## sibling. Group membership is encoded via the `data-radio-group`
## attribute set by `RadioSet.add`.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers mutate state directly.

import std/tables

import ../renderer
import ../events

type
  RadioButtonWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    label*: string
    value*: string                  ## Stable identifier for this option.
    selected*: bool
    disabled*: bool
    onSelect*: proc()               ## Fired when this radio becomes selected.
    color*: string

proc renderTree*(rb: RadioButtonWidget)
proc requestSelect*(rb: RadioButtonWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc radioGlyph(selected: bool): string =
  if selected: "(•)"
  else: "( )"

proc renderTree*(rb: RadioButtonWidget) =
  let r = rb.renderer
  clearTreeChildren(r, rb.node)
  let row = r.createElement("div")
  if rb.color.len > 0:
    r.setStyle(row, "color", rb.color)
  let text =
    if rb.label.len > 0: radioGlyph(rb.selected) & " " & rb.label
    else: radioGlyph(rb.selected)
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(rb.node, row)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newRadioButton*(renderer: TerminalRenderer;
                     label: string;
                     value: string = "";
                     selected: bool = false;
                     disabled: bool = false;
                     color: string = "";
                     onSelect: proc() = nil): RadioButtonWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "radio-button")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "data-radio-value",
                        (if value.len > 0: value else: label))
  renderer.setAttribute(node, "class", "radio-button")
  if selected:
    renderer.setAttribute(node, "data-selected", "true")
  else:
    renderer.setAttribute(node, "data-selected", "false")
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  let rb = RadioButtonWidget(
    renderer: renderer, node: node,
    label: label,
    value: (if value.len > 0: value else: label),
    selected: selected, disabled: disabled,
    onSelect: onSelect, color: color)
  rb.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    if rb.disabled: return
    let name = ev.key.key
    if name == "space" or name == "enter" or name == "return" or
       (ev.key.kind == kkChar and ev.key.rune == uint32(' '.ord)):
      rb.requestSelect())
  renderer.addEventListener(node, "click", proc(ev: TerminalEvent) =
    if rb.disabled: return
    rb.requestSelect())
  rb

# ----------------------------------------------------------------------------
# Selection
# ----------------------------------------------------------------------------

proc setSelected*(rb: RadioButtonWidget; selected: bool) =
  if rb.selected == selected: return
  rb.selected = selected
  rb.renderer.setAttribute(rb.node, "data-selected",
                           (if selected: "true" else: "false"))
  rb.renderTree()

proc requestSelect*(rb: RadioButtonWidget) =
  ## Bubble a `radio-select` event to the parent `RadioSet`. The set
  ## listens on its container node and deselects siblings before
  ## flipping this one to selected. When no parent set is wired, this
  ## just self-selects.
  if rb.disabled: return
  # Walk up to find a node with `data-widget="radio-set"`.
  var p: TerminalNode = rb.node.parent
  while p != nil:
    if p.attributes.getOrDefault("data-widget") == "radio-set":
      var ev = newCustomEvent("radio-select", rb.node.id)
      fireEventWith(p, "radio-select", ev)
      if rb.onSelect != nil: rb.onSelect()
      return
    p = p.parent
  # No parent set — just flip self.
  rb.setSelected(true)
  if rb.onSelect != nil: rb.onSelect()

proc setDisabled*(rb: RadioButtonWidget; disabled: bool) =
  rb.disabled = disabled
  if disabled:
    rb.renderer.setAttribute(rb.node, "disabled", "true")
    rb.renderer.setAttribute(rb.node, "data-focusable", "false")
  else:
    rb.renderer.removeAttribute(rb.node, "disabled")
    rb.renderer.setAttribute(rb.node, "data-focusable", "true")

proc id*(rb: RadioButtonWidget): int {.inline.} = rb.node.id
