## widgets/tabbed_content.nim — Tier-2 `TabbedContent` widget (M14).
##
## Port of `textual/widgets/tabbed_content.py` (~716 LOC) — pragmatic
## core. Composes a `Tabs` strip on top of a `ContentSwitcher` so the
## active tab routes the visible pane.
##
## API surface:
##
##   * `newTabbedContent(r, onChange)`  — empty
##   * `addTab(tc, id, label, paneNode)` — append a tab + pane
##   * `switchTo(tc, id)` — activate
##   * `activeTabId(tc)`  — current id
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ./tabs
import ./content_switcher

# ----------------------------------------------------------------------------
# Type
# ----------------------------------------------------------------------------

type
  TabbedContentWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    tabs*: TabsWidget
    switcher*: ContentSwitcherWidget
    onChange*: proc(oldId, newId: string)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTabbedContent*(renderer: TerminalRenderer;
                       width: int = 40;
                       onChange: proc(oldId,
                                      newId: string) = nil
                       ): TabbedContentWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "tabbed-content")
  renderer.setAttribute(node, "class", "tabbed-content")
  let tc = TabbedContentWidget(
    renderer: renderer, node: node,
    onChange: onChange)
  tc.tabs = newTabs(renderer, [], 0, width)
  tc.switcher = newContentSwitcher(renderer)
  renderer.appendChild(node, tc.tabs.node)
  renderer.appendChild(node, tc.switcher.node)

  # Wire the tabs' onChange to the switcher.
  tc.tabs.onChange = proc(oldIdx, newIdx: int) =
    if newIdx < 0 or newIdx >= tc.tabs.tabs.len: return
    let newId = tc.tabs.tabs[newIdx].id
    let oldId =
      if oldIdx >= 0 and oldIdx < tc.tabs.tabs.len: tc.tabs.tabs[oldIdx].id
      else: ""
    tc.switcher.switchTo(newId)
    if tc.onChange != nil:
      tc.onChange(oldId, newId)
  tc

proc addTab*(tc: TabbedContentWidget;
             id: string; label: string;
             pane: TerminalNode) =
  ## Append a tab with the given id + label, and mount the pane under
  ## the switcher. The first added tab becomes active automatically.
  tc.tabs.tabs.add Tab(id: id, label: label, disabled: false)
  tc.switcher.addPane(id, pane)
  tc.tabs.activeIndex = 0  # initial active is whatever was added first
  tc.tabs.renderTree()

proc switchTo*(tc: TabbedContentWidget; id: string) =
  for i, tab in tc.tabs.tabs:
    if tab.id == id:
      tc.tabs.setActive(i)   # propagates to the switcher via the wired callback
      return

proc activeTabId*(tc: TabbedContentWidget): string =
  tc.tabs.activeId

proc id*(tc: TabbedContentWidget): int {.inline.} = tc.node.id
