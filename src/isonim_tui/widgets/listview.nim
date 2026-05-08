## widgets/listview.nim — Tier-2 `ListView` widget (M14).
##
## Port of `textual/widgets/listview.py` (~396 LOC) — pragmatic core.
## A vertical list of focusable items where exactly one is highlighted
## at a time. Navigation:
##
##   * Up / Down       — move highlight one row
##   * PageUp / PageDown — move highlight one viewport
##   * Home / End      — jump to first / last
##   * Enter           — fires `activate(index)`
##
## Highlight changes fire `onHighlight(oldIdx, newIdx)`. Item content is
## a free-form string per item; layout reserves `viewportHeight` rows
## and clips longer lists with internal scrolling so the highlighted
## row stays in view.
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
  ListItem* = object
    ## A single ListView entry. `id` is optional; `label` is the visible
    ## text. `disabled` items participate in the chain but cannot be
    ## activated and are skipped over by Up / Down navigation.
    id*: string
    label*: string
    disabled*: bool

  ListViewWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    items*: seq[ListItem]
    highlightedIndex*: int            ## -1 = nothing highlighted
    width*: int                       ## Inner width in cells.
    viewportHeight*: int
    scrollY*: int
    border*: BorderStyle
    borderColor*: string
    color*: string
    onHighlight*: proc(oldIdx, newIdx: int)
    onActivate*: proc(idx: int)

# ----------------------------------------------------------------------------
# Forward declarations.
# ----------------------------------------------------------------------------
proc renderTree*(lv: ListViewWidget)
proc setHighlight*(lv: ListViewWidget; idx: int)
proc moveDown*(lv: ListViewWidget)
proc moveUp*(lv: ListViewWidget)
proc pageDown*(lv: ListViewWidget)
proc pageUp*(lv: ListViewWidget)
proc moveHome*(lv: ListViewWidget)
proc moveEnd*(lv: ListViewWidget)
proc activateCurrent*(lv: ListViewWidget)

# ----------------------------------------------------------------------------
# Tree builder
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

proc ensureScroll(lv: ListViewWidget) =
  ## Adjust scrollY so the highlighted row is visible inside the
  ## viewport.
  if lv.viewportHeight <= 0: return
  if lv.highlightedIndex < 0: return
  if lv.highlightedIndex < lv.scrollY:
    lv.scrollY = lv.highlightedIndex
  let bottom = lv.scrollY + lv.viewportHeight - 1
  if lv.highlightedIndex > bottom:
    lv.scrollY = lv.highlightedIndex - lv.viewportHeight + 1
  if lv.scrollY < 0: lv.scrollY = 0

proc renderTree*(lv: ListViewWidget) =
  let r = lv.renderer
  clearTreeChildren(r, lv.node)
  let glyphs = bordersGlyphs(lv.border)
  let useBorder = lv.border != bsNone
  if useBorder:
    emitRow(r, lv.node, topBorderRow(glyphs, lv.width), lv.borderColor)
  ensureScroll(lv)
  let visible = max(0, min(lv.items.len - lv.scrollY, lv.viewportHeight))
  for i in 0 ..< visible:
    let absoluteIdx = lv.scrollY + i
    let item = lv.items[absoluteIdx]
    let body = padOrTruncate(item.label, lv.width)
    let isHighlight = absoluteIdx == lv.highlightedIndex
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, lv.node, row, lv.color, isHighlight, item.disabled)
  for _ in visible ..< lv.viewportHeight:
    let body = spaces(lv.width)
    let row =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, lv.node, row, lv.borderColor)
  if useBorder:
    emitRow(r, lv.node, bottomBorderRow(glyphs, lv.width), lv.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newListView*(renderer: TerminalRenderer;
                  items: openArray[ListItem] = [];
                  width: int = 30;
                  viewportHeight: int = 6;
                  border: BorderStyle = bsNone;
                  borderColor: string = "";
                  color: string = "";
                  onHighlight: proc(oldIdx, newIdx: int) = nil;
                  onActivate: proc(idx: int) = nil): ListViewWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "list-view")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "list-view")
  var its: seq[ListItem] = @[]
  for i in items: its.add i
  let initialHl =
    if its.len > 0: 0
    else: -1
  let lv = ListViewWidget(
    renderer: renderer, node: node,
    items: its,
    highlightedIndex: initialHl,
    width: max(1, width),
    viewportHeight: max(1, viewportHeight),
    scrollY: 0,
    border: border, borderColor: borderColor, color: color,
    onHighlight: onHighlight, onActivate: onActivate)
  if initialHl >= 0:
    renderer.setAttribute(node, "data-highlighted", $initialHl)
  lv.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "down", "Down":         lv.moveDown()
    of "up", "Up":             lv.moveUp()
    of "pagedown", "PageDown", "pageDown": lv.pageDown()
    of "pageup", "PageUp", "pageUp":       lv.pageUp()
    of "home", "Home":         lv.moveHome()
    of "end", "End":           lv.moveEnd()
    of "enter", "return":      lv.activateCurrent()
    else: discard)
  lv

# ----------------------------------------------------------------------------
# Mutation helpers
# ----------------------------------------------------------------------------

proc nextEnabledFrom(lv: ListViewWidget; start: int; step: int): int =
  ## Walk through items in `step` direction starting at `start`,
  ## returning the first enabled index. Returns -1 if none found.
  var i = start
  while i >= 0 and i < lv.items.len:
    if not lv.items[i].disabled: return i
    i += step
  -1

proc setHighlight*(lv: ListViewWidget; idx: int) =
  if lv.items.len == 0:
    lv.highlightedIndex = -1
    lv.renderTree()
    return
  let target = max(0, min(idx, lv.items.len - 1))
  if target == lv.highlightedIndex: return
  let oldIdx = lv.highlightedIndex
  lv.highlightedIndex = target
  lv.renderer.setAttribute(lv.node, "data-highlighted", $target)
  lv.renderTree()
  if lv.onHighlight != nil:
    lv.onHighlight(oldIdx, target)

proc moveDown*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let cur = lv.highlightedIndex
  let nextIdx = nextEnabledFrom(lv, cur + 1, 1)
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc moveUp*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let cur = lv.highlightedIndex
  let nextIdx = nextEnabledFrom(lv, cur - 1, -1)
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc pageDown*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let cur = lv.highlightedIndex
  let target = min(cur + lv.viewportHeight, lv.items.len - 1)
  let nextIdx = nextEnabledFrom(lv, target, -1)  # walk back to find enabled
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc pageUp*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let cur = lv.highlightedIndex
  let target = max(cur - lv.viewportHeight, 0)
  let nextIdx = nextEnabledFrom(lv, target, 1)
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc moveHome*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let nextIdx = nextEnabledFrom(lv, 0, 1)
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc moveEnd*(lv: ListViewWidget) =
  if lv.items.len == 0: return
  let nextIdx = nextEnabledFrom(lv, lv.items.len - 1, -1)
  if nextIdx >= 0:
    lv.setHighlight(nextIdx)

proc activateCurrent*(lv: ListViewWidget) =
  if lv.highlightedIndex < 0 or lv.highlightedIndex >= lv.items.len: return
  if lv.items[lv.highlightedIndex].disabled: return
  if lv.onActivate != nil:
    lv.onActivate(lv.highlightedIndex)
  fireEvent(lv.node, "activate")

proc addItem*(lv: ListViewWidget; item: ListItem) =
  lv.items.add item
  if lv.highlightedIndex < 0 and not item.disabled:
    lv.highlightedIndex = lv.items.len - 1
  lv.renderTree()

proc setItems*(lv: ListViewWidget; items: openArray[ListItem]) =
  var its: seq[ListItem] = @[]
  for it in items: its.add it
  lv.items = its
  lv.scrollY = 0
  lv.highlightedIndex =
    if its.len > 0: nextEnabledFrom(lv, 0, 1)
    else: -1
  lv.renderTree()

proc id*(lv: ListViewWidget): int {.inline.} = lv.node.id
