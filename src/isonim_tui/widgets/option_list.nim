## widgets/option_list.nim — Tier-2 `OptionList` widget (M14).
##
## Port of `textual/widgets/option_list.py` (~1039 LOC) — pragmatic
## core. A scrollable list of options, separators, and disabled
## headings. The selectable rows behave like ListView; separators and
## headings render but are skipped by Up / Down navigation.
##
## API overlap with ListView is intentional — Textual ships both as
## first-class widgets because OptionList carries the
## separator/heading taxonomy that callers building a menu / picker
## need.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  OptionRowKind* = enum
    orkOption       ## Selectable entry.
    orkSeparator    ## Horizontal rule (─).
    orkHeading      ## Group title (rendered, not selectable).

  OptionRow* = object
    kind*: OptionRowKind
    id*: string
    label*: string
    disabled*: bool

  OptionListWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    rows*: seq[OptionRow]
    highlightedIndex*: int           ## -1 = nothing
    width*: int
    viewportHeight*: int
    scrollY*: int
    border*: BorderStyle
    borderColor*: string
    color*: string
    onHighlight*: proc(oldIdx, newIdx: int)
    onSelect*: proc(idx: int; rowId: string)

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(ol: OptionListWidget)
proc setHighlight*(ol: OptionListWidget; idx: int)
proc moveDown*(ol: OptionListWidget)
proc moveUp*(ol: OptionListWidget)
proc pageDown*(ol: OptionListWidget)
proc pageUp*(ol: OptionListWidget)
proc moveHome*(ol: OptionListWidget)
proc moveEnd*(ol: OptionListWidget)
proc activateCurrent*(ol: OptionListWidget)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "";
             reverse: bool = false; dim: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  if dim:
    r.setStyle(box, "italic", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc isSelectable(row: OptionRow): bool {.inline.} =
  row.kind == orkOption and not row.disabled

proc rowText(row: OptionRow; width: int): string =
  case row.kind
  of orkSeparator:
    var s = ""
    for _ in 0 ..< width: s.add "\xE2\x94\x80"  # ─
    s
  of orkHeading:
    padOrTruncate("[" & row.label & "]", width)
  of orkOption:
    padOrTruncate(row.label, width)

proc nextSelectableFrom(ol: OptionListWidget; start: int; step: int): int =
  var i = start
  while i >= 0 and i < ol.rows.len:
    if isSelectable(ol.rows[i]): return i
    i += step
  -1

proc ensureScroll(ol: OptionListWidget) =
  if ol.viewportHeight <= 0: return
  if ol.highlightedIndex < 0: return
  if ol.highlightedIndex < ol.scrollY:
    ol.scrollY = ol.highlightedIndex
  let bottom = ol.scrollY + ol.viewportHeight - 1
  if ol.highlightedIndex > bottom:
    ol.scrollY = ol.highlightedIndex - ol.viewportHeight + 1
  if ol.scrollY < 0: ol.scrollY = 0

proc renderTree*(ol: OptionListWidget) =
  let r = ol.renderer
  clearTreeChildren(r, ol.node)
  let glyphs = bordersGlyphs(ol.border)
  let useBorder = ol.border != bsNone
  if useBorder:
    emitRow(r, ol.node, topBorderRow(glyphs, ol.width), ol.borderColor)
  ensureScroll(ol)
  let visible = max(0, min(ol.rows.len - ol.scrollY, ol.viewportHeight))
  for i in 0 ..< visible:
    let abs = ol.scrollY + i
    let row = ol.rows[abs]
    let body = rowText(row, ol.width)
    let isHl = abs == ol.highlightedIndex
    let dim = row.kind == orkHeading or
              (row.kind == orkOption and row.disabled)
    let line =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, ol.node, line, ol.color, isHl, dim)
  for _ in visible ..< ol.viewportHeight:
    let body = spaces(ol.width)
    let line =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, ol.node, line, ol.borderColor)
  if useBorder:
    emitRow(r, ol.node, bottomBorderRow(glyphs, ol.width), ol.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newOptionList*(renderer: TerminalRenderer;
                    rows: openArray[OptionRow] = [];
                    width: int = 30;
                    viewportHeight: int = 6;
                    border: BorderStyle = bsNone;
                    borderColor: string = "";
                    color: string = "";
                    onHighlight: proc(oldIdx, newIdx: int) = nil;
                    onSelect: proc(idx: int;
                                   rowId: string) = nil): OptionListWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "option-list")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "option-list")
  var rs: seq[OptionRow] = @[]
  for r in rows: rs.add r
  let ol = OptionListWidget(
    renderer: renderer, node: node,
    rows: rs, highlightedIndex: -1,
    width: max(1, width),
    viewportHeight: max(1, viewportHeight),
    scrollY: 0,
    border: border, borderColor: borderColor, color: color,
    onHighlight: onHighlight, onSelect: onSelect)
  # Auto-pick first selectable row.
  ol.highlightedIndex = nextSelectableFrom(ol, 0, 1)
  ol.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "down", "Down":         ol.moveDown()
    of "up", "Up":             ol.moveUp()
    of "pagedown", "PageDown", "pageDown": ol.pageDown()
    of "pageup", "PageUp", "pageUp":       ol.pageUp()
    of "home", "Home":         ol.moveHome()
    of "end", "End":           ol.moveEnd()
    of "enter", "return":      ol.activateCurrent()
    else: discard)
  ol

# ----------------------------------------------------------------------------
# Navigation
# ----------------------------------------------------------------------------

proc setHighlight*(ol: OptionListWidget; idx: int) =
  if ol.rows.len == 0:
    ol.highlightedIndex = -1
    ol.renderTree()
    return
  let target = max(0, min(idx, ol.rows.len - 1))
  if not isSelectable(ol.rows[target]): return
  if target == ol.highlightedIndex: return
  let oldIdx = ol.highlightedIndex
  ol.highlightedIndex = target
  ol.renderer.setAttribute(ol.node, "data-highlighted", $target)
  ol.renderTree()
  if ol.onHighlight != nil:
    ol.onHighlight(oldIdx, target)

proc moveDown*(ol: OptionListWidget) =
  let nextIdx = nextSelectableFrom(ol, ol.highlightedIndex + 1, 1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc moveUp*(ol: OptionListWidget) =
  let nextIdx = nextSelectableFrom(ol, ol.highlightedIndex - 1, -1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc pageDown*(ol: OptionListWidget) =
  let target = min(ol.highlightedIndex + ol.viewportHeight, ol.rows.len - 1)
  let nextIdx = nextSelectableFrom(ol, target, -1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc pageUp*(ol: OptionListWidget) =
  let target = max(ol.highlightedIndex - ol.viewportHeight, 0)
  let nextIdx = nextSelectableFrom(ol, target, 1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc moveHome*(ol: OptionListWidget) =
  let nextIdx = nextSelectableFrom(ol, 0, 1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc moveEnd*(ol: OptionListWidget) =
  let nextIdx = nextSelectableFrom(ol, ol.rows.len - 1, -1)
  if nextIdx >= 0: ol.setHighlight(nextIdx)

proc activateCurrent*(ol: OptionListWidget) =
  if ol.highlightedIndex < 0 or ol.highlightedIndex >= ol.rows.len: return
  let row = ol.rows[ol.highlightedIndex]
  if not isSelectable(row): return
  if ol.onSelect != nil:
    ol.onSelect(ol.highlightedIndex, row.id)
  fireEvent(ol.node, "select")

proc addOption*(ol: OptionListWidget; row: OptionRow) =
  ol.rows.add row
  if ol.highlightedIndex < 0 and isSelectable(row):
    ol.highlightedIndex = ol.rows.len - 1
  ol.renderTree()

proc setRows*(ol: OptionListWidget; rows: openArray[OptionRow]) =
  var rs: seq[OptionRow] = @[]
  for r in rows: rs.add r
  ol.rows = rs
  ol.scrollY = 0
  ol.highlightedIndex = nextSelectableFrom(ol, 0, 1)
  ol.renderTree()

proc id*(ol: OptionListWidget): int {.inline.} = ol.node.id
