## widgets/tabs.nim — Tier-2 `Tabs` widget (M14).
##
## Port of `textual/widgets/_tabs.py` (~874 LOC) — pragmatic core. A
## horizontal list of clickable tab labels with one active tab. The
## widget owns:
##
##   * an ordered list of `Tab` records (id, label, optional icon),
##   * an `activeIndex` cursor,
##   * an `onChange(oldIdx, newIdx)` callback,
##   * keyboard navigation: Left / Right move the active tab; Home /
##     End jump to extremes.
##
## The visible representation is one row of `─ Tab1 ─ Tab2 ─ Tab3 ─`
## with the active tab shown in reverse-video. This matches Textual's
## default behaviour closely enough for the load-bearing tests; the
## full underline/overline panel-attachment ornamentation is deferred.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ../events
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  Tab* = object
    ## A single tab entry. Identifier `id` is used by `selectById`;
    ## `label` is what the user sees.
    id*: string
    label*: string
    disabled*: bool

  TabsWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    tabs*: seq[Tab]
    activeIndex*: int
    width*: int                    ## Inner width in cells.
    onChange*: proc(oldIdx, newIdx: int)
    color*: string
    activeColor*: string

# ----------------------------------------------------------------------------
# Forward declarations so the keydown closure resolves.
# ----------------------------------------------------------------------------
proc renderTree*(t: TabsWidget)
proc setActive*(t: TabsWidget; idx: int)
proc moveLeft*(t: TabsWidget)
proc moveRight*(t: TabsWidget)
proc moveHome*(t: TabsWidget)
proc moveEnd*(t: TabsWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "";
             reverse: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderTree*(t: TabsWidget) =
  ## Render the tab strip as a single row. Active tab is bracketed by
  ## ` [Tab] `; others by `  Tab  `. Truncates / pads to `t.width`.
  let r = t.renderer
  clearTreeChildren(r, t.node)
  var line = ""
  for i, tab in t.tabs:
    if i > 0:
      line.add " "
    if i == t.activeIndex:
      line.add "[" & tab.label & "]"
    else:
      line.add " " & tab.label & " "
  let body = padOrTruncate(line, t.width)
  emitRow(r, t.node, body, t.color, false)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTabs*(renderer: TerminalRenderer;
              tabs: openArray[Tab];
              activeIndex: int = 0;
              width: int = 40;
              onChange: proc(oldIdx, newIdx: int) = nil;
              color: string = "";
              activeColor: string = ""): TabsWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "tabs")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "tabs")
  var tabList: seq[Tab] = @[]
  for tab in tabs: tabList.add tab
  let initialIndex =
    if tabList.len == 0: 0
    elif activeIndex < 0: 0
    elif activeIndex >= tabList.len: tabList.len - 1
    else: activeIndex
  let t = TabsWidget(
    renderer: renderer, node: node,
    tabs: tabList, activeIndex: initialIndex,
    width: max(1, width),
    onChange: onChange,
    color: color, activeColor: activeColor)
  renderer.setAttribute(node, "data-active-index", $initialIndex)
  t.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "left", "Left":  t.moveLeft()
    of "right", "Right": t.moveRight()
    of "home", "Home":  t.moveHome()
    of "end", "End":    t.moveEnd()
    else: discard)
  t

# ----------------------------------------------------------------------------
# Mutators
# ----------------------------------------------------------------------------

proc setActive*(t: TabsWidget; idx: int) =
  if t.tabs.len == 0: return
  let target = max(0, min(idx, t.tabs.len - 1))
  if target == t.activeIndex: return
  let oldIdx = t.activeIndex
  t.activeIndex = target
  t.renderer.setAttribute(t.node, "data-active-index", $target)
  t.renderTree()
  if t.onChange != nil:
    t.onChange(oldIdx, target)

proc setActiveById*(t: TabsWidget; id: string) =
  for i, tab in t.tabs:
    if tab.id == id:
      t.setActive(i)
      return

proc activeId*(t: TabsWidget): string =
  if t.tabs.len == 0 or t.activeIndex < 0 or t.activeIndex >= t.tabs.len:
    return ""
  t.tabs[t.activeIndex].id

proc moveLeft*(t: TabsWidget) =
  if t.tabs.len == 0: return
  if t.activeIndex == 0:
    t.setActive(t.tabs.len - 1)  # wrap
  else:
    t.setActive(t.activeIndex - 1)

proc moveRight*(t: TabsWidget) =
  if t.tabs.len == 0: return
  if t.activeIndex == t.tabs.len - 1:
    t.setActive(0)               # wrap
  else:
    t.setActive(t.activeIndex + 1)

proc moveHome*(t: TabsWidget) =
  t.setActive(0)

proc moveEnd*(t: TabsWidget) =
  t.setActive(t.tabs.len - 1)

proc id*(t: TabsWidget): int {.inline.} = t.node.id
