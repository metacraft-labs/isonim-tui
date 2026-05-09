## examples/ports/buttons_horizontal_row.nim — Nim port (M23 Batch-3).
##
## Three small buttons arranged left-to-right inside a bordered
## horizontal Container. Exercises the new `clHorizontal` default
## render path with multi-row children (each Button emits a 3-row
## bordered glyph stack).

import isonim_tui

proc buildButtonsHorizontalRowApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let labels = ["OK", "Cancel", "Apply"]
  var totalInner = 0
  for l in labels: totalInner += l.len + 4 + 2  # inner = label+4, +2 border
  let row = newContainer(r,
    width = min(totalInner + 2, h.cols - 2), viewportHeight = 3,
    border = bsSolid, layout = clHorizontal)
  for label in labels:
    let b = newButton(r, label)
    row.append(b.node)
  r.appendChild(root, row.node)
  root
