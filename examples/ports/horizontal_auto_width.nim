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

  # Compute the auto-width: sum of label widths.
  var total = 0
  for l in labels: total += cellWidth(l)

  # Container inner width: at least the sum of label widths, capped at
  # terminal cols minus 2 for the border so the right border stays on
  # screen.
  let innerWidth = min(max(total, h.cols - 2), h.cols - 2)
  let row = newContainer(r, width = innerWidth,
                        viewportHeight = 3,
                        border = bsSolid,
                        layout = clHorizontal)
  for l in labels:
    let s = newStatic(r, l, width = cellWidth(l), height = 1)
    row.append(s.node)
  r.appendChild(root, row.node)
  root
