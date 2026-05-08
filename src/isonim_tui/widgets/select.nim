## widgets/select.nim — Tier-2 `Select` widget (M14).
##
## Port of `textual/widgets/select.py` (~719 LOC) — pragmatic core. A
## focusable input that displays the current value as a single-line
## button. Pressing `Enter` (or `Space`) opens a `Modal` containing
## an `OptionList` of choices. Arrow keys navigate, `Enter` selects,
## `Escape` cancels. The dropdown closes; focus returns to the
## Select with the new value (or unchanged on cancel).
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import std/[strutils]

import ../renderer
import ../events
import ../testing/harness as harnessMod
import ../css/properties
import ./borders
import ./modal
import ./option_list

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  SelectChoice* = object
    id*: string
    label*: string
    disabled*: bool

  SelectWidget* = ref object
    h*: TerminalTestHarness
    node*: TerminalNode               ## The visible "button" node.
    choices*: seq[SelectChoice]
    selectedIndex*: int               ## -1 = no selection
    width*: int
    border*: BorderStyle
    borderColor*: string
    placeholder*: string
    onChange*: proc(oldIdx, newIdx: int; newId: string)
    modal*: ModalWidget               ## Dropdown — created on first open.
    optionList*: OptionListWidget

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(s: SelectWidget)
proc openDropdown*(s: SelectWidget)
proc closeDropdown*(s: SelectWidget; cancelled: bool = false)

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

proc selectedLabel(s: SelectWidget): string =
  if s.selectedIndex < 0 or s.selectedIndex >= s.choices.len:
    return s.placeholder
  s.choices[s.selectedIndex].label

proc renderTree*(s: SelectWidget) =
  let r = s.h.renderer
  clearTreeChildren(r, s.node)
  let glyphs = bordersGlyphs(s.border)
  let useBorder = s.border != bsNone
  if useBorder:
    emitRow(r, s.node, topBorderRow(glyphs, s.width), s.borderColor)
  let label = selectedLabel(s)
  let arrow = " \xE2\x96\xBC"   # ▼
  let inner = padOrTruncate(label & arrow, s.width)
  let line =
    if useBorder: glyphs.left & inner & glyphs.right
    else: inner
  emitRow(r, s.node, line, s.borderColor)
  if useBorder:
    emitRow(r, s.node, bottomBorderRow(glyphs, s.width), s.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newSelect*(h: TerminalTestHarness;
                choices: openArray[SelectChoice];
                selectedIndex: int = -1;
                width: int = 20;
                border: BorderStyle = bsRound;
                borderColor: string = "";
                placeholder: string = "Select...";
                onChange: proc(oldIdx, newIdx: int;
                               newId: string) = nil): SelectWidget =
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "select")
  r.setAttribute(node, "data-focusable", "true")
  r.setAttribute(node, "class", "select")
  var cs: seq[SelectChoice] = @[]
  for c in choices: cs.add c
  let s = SelectWidget(
    h: h, node: node,
    choices: cs,
    selectedIndex: selectedIndex,
    width: max(4, width),
    border: border, borderColor: borderColor,
    placeholder: placeholder,
    onChange: onChange)
  s.renderTree()

  r.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    let lower = ev.key.key.toLowerAscii
    case lower
    of "enter", "return", "space":
      s.openDropdown()
    else:
      discard)
  r.addEventListener(node, "click", proc(ev: TerminalEvent) =
    s.openDropdown())
  s

# ----------------------------------------------------------------------------
# Dropdown
# ----------------------------------------------------------------------------

proc applySelection(s: SelectWidget; idx: int) =
  if idx < 0 or idx >= s.choices.len: return
  if s.choices[idx].disabled: return
  let oldIdx = s.selectedIndex
  s.selectedIndex = idx
  s.h.renderer.setAttribute(s.node, "data-selected-index", $idx)
  s.renderTree()
  s.h.flush()
  if s.onChange != nil:
    s.onChange(oldIdx, idx, s.choices[idx].id)

proc openDropdown*(s: SelectWidget) =
  ## Construct a modal hosting an OptionList; mount it; trap focus.
  if s.modal != nil and s.modal.isOpen: return

  # Build the OptionList from choices.
  var rows: seq[OptionRow] = @[]
  for c in s.choices:
    rows.add OptionRow(kind: orkOption, id: c.id,
                       label: c.label, disabled: c.disabled)
  let listHeight = min(8, max(2, rows.len + 2))
  let listWidth = max(s.width, 16)
  s.optionList = newOptionList(s.h.renderer, rows,
                                width = listWidth,
                                viewportHeight = listHeight)
  # Pre-highlight the current selection if any.
  if s.selectedIndex >= 0:
    s.optionList.setHighlight(s.selectedIndex)

  s.modal = newModal(s.h, "",
                     width = listWidth + 2,
                     height = listHeight + 2,
                     animDurationMs = 50.0)  # short — dropdowns feel snappy
  # Hook OptionList key handlers: Enter selects + closes; Escape
  # cancels.
  s.h.renderer.addEventListener(s.optionList.node, "keydown",
    proc(ev: TerminalEvent) =
      if ev.kind != ekKey: return
      let lower = ev.key.key.toLowerAscii
      case lower
      of "enter", "return":
        let idx = s.optionList.highlightedIndex
        if idx >= 0:
          s.applySelection(idx)
        s.closeDropdown(cancelled = false)
      of "escape", "esc":
        s.closeDropdown(cancelled = true)
      else: discard)
  # Mount the option list under the modal's content mount before opening.
  s.h.renderer.appendChild(s.modal.contentMount, s.optionList.node)
  s.modal.opener = s.node
  s.modal.open()

proc closeDropdown*(s: SelectWidget; cancelled: bool = false) =
  if s.modal == nil: return
  if not s.modal.isOpen: return
  s.modal.close()

proc setSelectedIndex*(s: SelectWidget; idx: int) =
  s.applySelection(idx)

proc selectedId*(s: SelectWidget): string =
  if s.selectedIndex < 0 or s.selectedIndex >= s.choices.len: return ""
  s.choices[s.selectedIndex].id

proc id*(s: SelectWidget): int {.inline.} = s.node.id
