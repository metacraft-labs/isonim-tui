## examples/ports/tabs_basic.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's `tabs_basic.py` (and similar) snapshot apps: a
## `Tabs` widget with three tab entries plus a Static body line that
## reflects the active tab. Exercises the M11 Tabs surface in its
## simplest form (no content-switcher integration).
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const TabsBasicEntries = [
  Tab(id: "one", label: "One"),
  Tab(id: "two", label: "Two"),
  Tab(id: "three", label: "Three")]

proc buildTabsBasicStack(r: TerminalRenderer;
                         tabsWidth, bodyWidth, bodyHeight,
                         outerWidth, outerHeight: int): TerminalNode =
  ## Build a vertical `Container` with a `Tabs` row and a bordered
  ## `Static` body line beneath it. Returns the container's `.node`
  ## for the DSL to embed.
  let tabs = newTabs(r, tabs = TabsBasicEntries,
                     activeIndex = 0, width = tabsWidth)
  let body = newStatic(r, "Active tab: One", width = bodyWidth,
                       height = bodyHeight, border = bsSolid)
  let outer = newContainer(r, width = outerWidth,
                           viewportHeight = outerHeight,
                           layout = clVertical)
  outer.append(tabs.node)
  outer.append(body.node)
  outer.node

proc buildTabsBasicApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let tabsWidth = max(20, h.cols)
  let bodyWidth = max(20, h.cols - 2)
  let bodyHeight = max(1, h.rows - 4)
  let outerWidth = max(20, h.cols)
  # 1 row for Tabs + (1 + 2) for the bordered Static body =
  # `1 + max(1, h.rows - 4) + 2` rows total.
  let outerHeight = max(7, 1 + bodyHeight + 2)
  result = ui(r):
    tdiv(class = "tabs-basic-port"):
      buildTabsBasicStack(r, tabsWidth, bodyWidth, bodyHeight,
                          outerWidth, outerHeight)
