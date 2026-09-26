## widgets/menu.nim — Tier-2 `Menu` widget.
##
## A transient list of COMMANDS: it opens at a point in the reader's
## attention, one command is run or none is, and it closes. That last
## clause is the difference from `Select`, which commits a VALUE and keeps
## showing it afterwards; a menu has nothing to show once it has done its
## job, so it has no selected index — only the highlight while it is open
## and a record of the last command that ran.
##
## Keyboard contract, while open:
##
##   * `Up` / `Down`  move the highlight, skipping disabled commands, and
##                    stop at the ends (no wrap — the same as ListView and
##                    OptionList);
##   * `Home` / `End` jump to the first / last enabled command;
##   * `Enter`        runs the highlighted command and closes the menu;
##   * `Escape`       closes the menu without running anything.
##
## Built from the library's own parts, the same way `SelectWidget` builds
## its dropdown: an `OptionListWidget` mounted inside a `ModalWidget`, so
## the focus trap, the overlay layer and the open/close animation are the
## modal's, and the motion is the option list's. What this module adds is
## the part neither of those has on its own — `Enter` both RUNS and
## CLOSES, and `Escape` closes without running — which a host composing
## the two by hand had to write itself.
##
## Charter §1: every public type is a value object; the widget handle is a
## `ref` so callers can mutate state directly.

import std/strutils

import ../renderer
import ../events
import ../testing/harness as harnessMod
import ./modal
import ./option_list

type
  MenuItem* = object
    id*: string
    label*: string
    disabled*: bool

  MenuWidget* = ref object
    h*: TerminalTestHarness
    items*: seq[MenuItem]
    optionList*: OptionListWidget   ## Where the keys land while open.
    modal*: ModalWidget             ## The overlay and its focus trap.
    lastActivated*: int             ## Index of the last command run; -1.
    onActivate*: proc(idx: int; id: string)
    onDismiss*: proc()

proc close*(m: MenuWidget)

proc activate(m: MenuWidget; idx: int) =
  if idx < 0 or idx >= m.items.len: return
  if m.items[idx].disabled: return
  m.lastActivated = idx
  m.close()
  if m.onActivate != nil:
    m.onActivate(idx, m.items[idx].id)

proc newMenu*(h: TerminalTestHarness;
              items: openArray[MenuItem];
              width: int = 24;
              animDurationMs: float64 = 50.0;
              onActivate: proc(idx: int; id: string) = nil;
              onDismiss: proc() = nil): MenuWidget =
  ## Construct a CLOSED menu. `open` shows it.
  var its: seq[MenuItem] = @[]
  var rows: seq[OptionRow] = @[]
  for it in items:
    its.add it
    rows.add OptionRow(kind: orkOption, id: it.id, label: it.label,
                       disabled: it.disabled)
  let listHeight = min(8, max(2, rows.len + 2))
  let m = MenuWidget(h: h, items: its, lastActivated: -1,
                     onActivate: onActivate, onDismiss: onDismiss)
  m.optionList = newOptionList(h.renderer, rows, width = max(4, width),
                               viewportHeight = listHeight,
                               onSelect = proc(idx: int; rowId: string) =
                                 m.activate(idx))
  h.renderer.setAttribute(m.optionList.node, "data-widget", "menu")
  m.modal = newModal(h, "", width = max(4, width) + 2,
                     height = listHeight + 2,
                     animDurationMs = animDurationMs)
  h.renderer.appendChild(m.modal.contentMount, m.optionList.node)
  # `Enter` reaches `activate` through the option list's own `onSelect`;
  # `Escape` is the one key the option list does not answer, so the menu
  # answers it on the list (where focus is while open) AND on the modal's
  # panel (the trap's root), which is where a host that routes keys to the
  # focused region delivers it.
  proc onEscape(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    let lower = ev.key.key.toLowerAscii
    if lower == "escape" or lower == "esc":
      if m.modal.state in {msOpen, msOpening}:
        m.close()
        if m.onDismiss != nil: m.onDismiss()
  h.renderer.addEventListener(m.optionList.node, "keydown", onEscape)
  h.renderer.addEventListener(m.modal.panel, "keydown", onEscape)
  m

proc open*(m: MenuWidget) =
  ## Show the menu with the highlight on the first enabled command.
  if m.modal.state in {msOpen, msOpening}: return
  m.optionList.moveHome()
  m.modal.open()

proc close*(m: MenuWidget) =
  m.modal.close()

proc isOpen*(m: MenuWidget): bool {.inline.} =
  ## True from the moment `open` is called until `close` is — the closing
  ## animation is not "open" as far as a reader choosing a command is
  ## concerned.
  m.modal.state in {msOpen, msOpening}

proc highlightedIndex*(m: MenuWidget): int {.inline.} =
  m.optionList.highlightedIndex

proc setHighlight*(m: MenuWidget; idx: int) =
  m.optionList.setHighlight(idx)

proc node*(m: MenuWidget): TerminalNode {.inline.} =
  ## The node keys are delivered to while the menu is open.
  m.optionList.node
