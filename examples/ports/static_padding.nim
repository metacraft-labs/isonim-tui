## examples/ports/static_padding.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `static_padding.py`-class apps that exercise
## a `Static` rendered at several widths to demonstrate cell padding /
## auto-truncation. Three bordered Statics inside a vertical Container,
## each at a different inner width, all displaying the same text.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const PadWidths = [10, 20, 30]
const PadBody = "padded"

proc buildPaddingStack(r: TerminalRenderer; width, viewportHeight: int):
    TerminalNode =
  ## Build a vertical `Container` populated with one bordered Static
  ## per width in `PadWidths`. Returns the container's `.node` for the
  ## DSL to embed.
  let outer = newContainer(r, width = width,
                           viewportHeight = viewportHeight,
                           layout = clVertical)
  for w in PadWidths:
    let s = newStatic(r, PadBody, width = w, height = 1, border = bsSolid)
    outer.append(s.node)
  outer.node

proc buildStaticPaddingApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  # Sum of bordered heights = 3 * (1 + 2) = 9 rows. Use a 10-row
  # container so the natural stack fits with one trailing pad row.
  let width = max(34, h.cols - 2)
  let viewportHeight = max(10, h.rows)
  result = ui(r):
    tdiv(class = "static-padding-port"):
      buildPaddingStack(r, width, viewportHeight)
