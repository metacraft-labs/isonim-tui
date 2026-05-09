## examples/ports/listview_basic.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's small-list snapshot apps. Mounts a `ListView`
## with five entries, exercises the M14 surface in its simplest form
## (default border, default colours, no on-highlight handler).

import isonim_tui

proc buildListViewBasicApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let lv = newListView(r,
    items = [
      ListItem(id: "a", label: "Apple"),
      ListItem(id: "b", label: "Banana"),
      ListItem(id: "c", label: "Cherry"),
      ListItem(id: "d", label: "Date"),
      ListItem(id: "e", label: "Elderberry")],
    width = max(20, h.cols - 4),
    viewportHeight = max(5, h.rows - 2),
    border = bsSolid)
  r.appendChild(root, lv.node)
  root
