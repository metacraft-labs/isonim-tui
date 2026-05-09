## examples/ports/horizontal_auto_width.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/horizontal_auto_width.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class HorizontalAutoWidth(App):
##       def compose(self) -> ComposeResult:
##           yield Horizontal(
##               Static("Docked left 1", id="dock-1"),
##               Static("Docked left 2", id="dock-2"),
##               Static("Widget 1", classes="widget"),
##               Static("Widget 2", classes="widget"),
##               id="horizontal",
##           )
##
## Four `Static` widgets inside an auto-width horizontal container.
## isonim-tui's M11 Container computes the row width from the visible
## children; we emit the same labels so the cell-content matches.

import isonim_tui

proc buildHorizontalAutoWidthApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let labels = @[
    "Docked left 1", "Docked left 2", "Widget 1", "Widget 2"]

  # Compute the auto-width: sum of label widths + 2 for the border.
  var total = 2
  for l in labels: total += cellWidth(l)

  let row = newContainer(r, width = max(total, h.cols),
                        viewportHeight = 3,
                        border = bsSolid,
                        layout = clHorizontal)
  for l in labels:
    let s = newStatic(r, l, width = cellWidth(l), height = 1)
    row.append(s.node)
  r.appendChild(root, row.node)
  root
