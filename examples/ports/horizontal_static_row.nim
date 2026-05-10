## examples/ports/horizontal_static_row.nim — Nim port (M23 Batch-3).
##
## Demonstrates the new `clHorizontal` default render path landed
## alongside Batch 3. Three labelled `Static` widgets at fixed cell
## widths are stacked left-to-right inside a bordered Container; the
## snapshot captures the side-by-side layout.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const HorizontalLabels = ["alpha", "beta", "gamma"]
const HorizontalCellWidth = 10

proc buildHorizontalRow(r: TerminalRenderer; rowWidth: int): TerminalNode =
  ## Build a horizontal bordered `Container` populated with one labelled
  ## `Static` per label, each tagged with a `data-cell-width` attribute.
  ## Returns the container's `.node` for the DSL to embed.
  let row = newContainer(r, width = rowWidth, viewportHeight = 3,
                         border = bsSolid, layout = clHorizontal)
  for label in HorizontalLabels:
    let s = newStatic(r, label, width = HorizontalCellWidth, height = 1)
    r.setAttribute(s.node, "data-cell-width", $HorizontalCellWidth)
    row.append(s.node)
  row.node

proc buildHorizontalStaticRowApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let innerWidth = HorizontalCellWidth * HorizontalLabels.len + 2
  let rowWidth = min(innerWidth, h.cols - 2)
  result = ui(r):
    tdiv(class = "horizontal-static-row-port"):
      buildHorizontalRow(r, rowWidth)
