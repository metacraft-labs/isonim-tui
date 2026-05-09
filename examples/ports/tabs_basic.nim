## examples/ports/tabs_basic.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's `tabs_basic.py` (and similar) snapshot apps: a
## `Tabs` widget with three tab entries plus a Static body line that
## reflects the active tab. Exercises the M11 Tabs surface in its
## simplest form (no content-switcher integration).
##
## Originally Tabs and the bordered Static were mounted directly
## under the root (Batch-3 workaround) because `renderVertical` only
## consumed the first text row of each direct child. The
## vertical-multi-row fix that landed alongside the renderHorizontal
## fix retired that workaround; the natural composition (Tabs + body
## stacked inside a vertical Container) now survives.

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

  # 1 row for Tabs + (1 + 2) for the bordered Static body =
  # `1 + max(1, h.rows - 4) + 2` rows total. Use a vertical Container
  # whose inner viewport accommodates the full stack.
  let outer = newContainer(r,
    width = max(20, h.cols),
    viewportHeight = max(7, 1 + max(1, h.rows - 4) + 2),
    layout = clVertical)
  outer.append(tabs.node)
  outer.append(body.node)
  r.appendChild(root, outer.node)
  root
