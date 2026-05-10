## examples/ports/listview_basic.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's small-list snapshot apps. Mounts a `ListView`
## with five entries, exercises the M14 surface in its simplest form
## (default border, default colours, no on-highlight handler).
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Reuses the existing `wListView` wrapper.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

const ListItems = [
  ListItem(id: "a", label: "Apple"),
  ListItem(id: "b", label: "Banana"),
  ListItem(id: "c", label: "Cherry"),
  ListItem(id: "d", label: "Date"),
  ListItem(id: "e", label: "Elderberry")]

proc buildListViewBasicApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "listview-basic-port"):
      wListView(r, ListItems, max(20, h.cols - 4),
                max(5, h.rows - 2), bsSolid)
