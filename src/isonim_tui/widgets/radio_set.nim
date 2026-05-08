## widgets/radio_set.nim — Tier-1b `RadioSet` widget.
##
## Port of `textual/widgets/_radio_set.py`. A radio set is a
## container of `RadioButton`s with exclusive selection semantics:
## selecting one deselects every sibling. Activation of a child
## button bubbles a synthetic `radio-select` event to the set; the
## set walks its children, deselects all, and selects the originator.
##
## Charter §1: value types throughout. The set is a `ref object` so
## callers can mutate it (add buttons, change disabled flag) and the
## change propagates.

import ../renderer
import ../events
import ./radio_button

type
  RadioSetWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    buttons*: seq[RadioButtonWidget]
    onChange*: proc(oldId, newId: int; newValue: string)
    disabled*: bool

# ----------------------------------------------------------------------------
# Selection logic
# ----------------------------------------------------------------------------

proc selectedIndex*(rs: RadioSetWidget): int =
  ## Index of the currently-selected button, or -1.
  for i, b in rs.buttons:
    if b.selected: return i
  return -1

proc selectedValue*(rs: RadioSetWidget): string =
  let i = rs.selectedIndex
  if i < 0: "" else: rs.buttons[i].value

proc selectById(rs: RadioSetWidget; targetId: int): tuple[oldId, newId: int;
                                                         newValue: string] =
  ## Walk children, deselect all, select the matching id. Returns the
  ## old + new selected-button ids and the new value string for the
  ## change callback.
  var oldId = 0
  var newId = 0
  var newValue = ""
  for b in rs.buttons:
    if b.selected:
      oldId = b.node.id
      b.setSelected(false)
  for b in rs.buttons:
    if b.node.id == targetId:
      b.setSelected(true)
      newId = b.node.id
      newValue = b.value
  (oldId: oldId, newId: newId, newValue: newValue)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newRadioSet*(renderer: TerminalRenderer;
                  onChange: proc(oldId, newId: int;
                                 newValue: string) = nil): RadioSetWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "radio-set")
  renderer.setAttribute(node, "class", "radio-set")
  let rs = RadioSetWidget(
    renderer: renderer, node: node,
    buttons: @[], onChange: onChange, disabled: false)

  renderer.addEventListener(node, "radio-select", proc(ev: TerminalEvent) =
    let change = selectById(rs, ev.targetId)
    if rs.onChange != nil:
      rs.onChange(change.oldId, change.newId, change.newValue))
  rs

proc add*(rs: RadioSetWidget; rb: RadioButtonWidget) =
  ## Add a radio button to the set. Mounts the button as a child of
  ## the set's node, applies the disabled flag if the set itself is
  ## disabled, and tags the button with the group id for downstream
  ## CSS selectors.
  rs.renderer.appendChild(rs.node, rb.node)
  rs.renderer.setAttribute(rb.node, "data-radio-group", $rs.node.id)
  if rs.disabled:
    rb.setDisabled(true)
  rs.buttons.add rb

proc addAll*(rs: RadioSetWidget;
             buttons: openArray[RadioButtonWidget]) =
  for b in buttons:
    rs.add(b)

proc selectIndex*(rs: RadioSetWidget; index: int) =
  ## Programmatically select the i-th button. Out-of-range no-ops.
  if index < 0 or index >= rs.buttons.len: return
  let target = rs.buttons[index]
  let change = selectById(rs, target.node.id)
  if rs.onChange != nil:
    rs.onChange(change.oldId, change.newId, change.newValue)

proc setDisabled*(rs: RadioSetWidget; disabled: bool) =
  rs.disabled = disabled
  for b in rs.buttons:
    b.setDisabled(disabled)

proc id*(rs: RadioSetWidget): int {.inline.} = rs.node.id
