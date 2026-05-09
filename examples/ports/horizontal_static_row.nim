## examples/ports/horizontal_static_row.nim — Nim port (M23 Batch-3).
##
## Demonstrates the new `clHorizontal` default render path landed
## alongside Batch 3. Three labelled `Static` widgets at fixed cell
## widths are stacked left-to-right inside a bordered Container; the
## snapshot captures the side-by-side layout.

import isonim_tui

proc buildHorizontalStaticRowApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let labels = ["alpha", "beta", "gamma"]
  let cellW = 10
  let innerWidth = cellW * labels.len + 2
  let row = newContainer(r,
    width = min(innerWidth, h.cols - 2), viewportHeight = 3,
    border = bsSolid, layout = clHorizontal)
  for label in labels:
    let s = newStatic(r, label, width = cellW, height = 1)
    r.setAttribute(s.node, "data-cell-width", $cellW)
    row.append(s.node)
  r.appendChild(root, row.node)
  root
