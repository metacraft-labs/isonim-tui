## examples/ports/tabs_basic.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's `tabs_basic.py` (and similar) snapshot apps: a
## `Tabs` widget with three tab entries plus a Static body line that
## reflects the active tab. Exercises the M11 Tabs surface in its
## simplest form (no content-switcher integration).

import isonim_tui

proc buildTabsBasicApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let tabs = newTabs(r,
    tabs = [
      Tab(id: "one", label: "One"),
      Tab(id: "two", label: "Two"),
      Tab(id: "three", label: "Three")],
    activeIndex = 0,
    width = max(20, h.cols))
  let body = newStatic(r, "Active tab: One",
                       width = max(20, h.cols - 2),
                       height = max(1, h.rows - 4),
                       border = bsSolid)

  # Mount the tabs and the bordered Static directly under the root —
  # M11's vertical Container only consumes one text-row per child,
  # which would crush the Static's top/bottom border rows.
  r.appendChild(root, tabs.node)
  r.appendChild(root, body.node)
  root
