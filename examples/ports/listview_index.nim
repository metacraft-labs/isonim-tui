## examples/ports/listview_index.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/listview_index.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class ListViewIndexApp(App):
##       CSS = "ListView { height: 10; }"
##       data = reactive(list(range(6)))
##       def __init__(self) -> None:
##           super().__init__()
##           self._menu = ListView()
##       def compose(self): yield self._menu
##       async def watch_data(self, data):
##           await self._menu.remove_children()
##           await self._menu.extend((ListItem(Label(str(v))) for v in data))
##           self._menu.index = len(self._menu) - 1
##       async def on_ready(self):
##           self.data = list(range(0, 30, 2))
##
## After mount the data settles to `[0, 2, 4, …, 28]` and the
## highlighted index is the last (14). The M14 ListView widget mirrors
## this through its own keyboard-driven selection (we drive it
## directly here — no async / `watch` plumbing needed for the
## snapshot).
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The post-mount Pilot needs the ListView's
## `.node` to focus and key-drive selection, so the DSL embeds the
## already-built node rather than going through `wListView` (which
## would only return the node, dropping the handle we need).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildListViewIndexApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer

  var items: seq[ListItem] = @[]
  var i = 0
  while i < 30:
    items.add ListItem(id: "i" & $i, label: $i)
    i += 2

  let lv = newListView(r, items = items,
                       width = max(20, h.cols - 2),
                       viewportHeight = 10,
                       border = bsSolid)

  result = ui(r):
    tdiv(class = "listview-index-port"):
      embedNode(lv.node)

  # The Python `watch_data` sets `self._menu.index = len(self._menu) - 1`
  # — drive the ListView's keyboard handler to land on the same row.
  let p = newPilot(h)
  p.focus(lv.node)
  for _ in 0 ..< (items.len - 1):
    p.press("down")
