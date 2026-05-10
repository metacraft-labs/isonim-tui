## examples/ports/buttons_horizontal_row.nim — Nim port (M23 Batch-3).
##
## Three small buttons arranged left-to-right inside a bordered
## horizontal Container. Exercises the new `clHorizontal` default
## render path with multi-row children (each Button emits a 3-row
## bordered glyph stack).
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const ButtonLabels = ["OK", "Cancel", "Apply"]

proc buildButtonsRow(r: TerminalRenderer; rowWidth: int): TerminalNode =
  ## Build a bordered horizontal `Container` with one `Button` per
  ## label. Returns the container's `.node` for the DSL to embed.
  let row = newContainer(r, width = rowWidth, viewportHeight = 3,
                         border = bsSolid, layout = clHorizontal)
  for label in ButtonLabels:
    let b = newButton(r, label)
    row.append(b.node)
  row.node

proc buildButtonsHorizontalRowApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  var totalInner = 0
  for l in ButtonLabels: totalInner += l.len + 4 + 2  # inner = label+4, +2 border
  let rowWidth = min(totalInner + 2, h.cols - 2)
  result = ui(r):
    tdiv(class = "buttons-horizontal-row-port"):
      buildButtonsRow(r, rowWidth)
