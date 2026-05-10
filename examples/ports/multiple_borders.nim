## examples/ports/multiple_borders.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `border-styles` snapshot apps that demonstrate
## the suite of `border` styles applied to a widget. One `Static` per
## BorderStyle in a vertical Container so the snapshot captures every
## glyph variant in one frame.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const StyleSamples* = [
  bsSolid, bsDashed, bsDouble, bsHeavy, bsAscii, bsRound]

proc buildBordersStack(r: TerminalRenderer;
                       width, viewportHeight, innerWidth: int): TerminalNode =
  ## Build a vertical `Container` with one bordered `Static` per
  ## sampled BorderStyle. Returns the container's `.node` for the DSL
  ## to embed.
  let outer = newContainer(r, width = width,
                           viewportHeight = viewportHeight,
                           layout = clVertical)
  for style in StyleSamples:
    let s = newStatic(r, $style, width = innerWidth,
                      height = 1, border = style)
    outer.append(s.node)
  outer.node

proc buildMultipleBordersApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  # Sum of bordered heights = 6 * (1 + 2) = 18 rows. Use an
  # 18-row inner viewport so every variant lands in the snapshot.
  let width = max(36, h.cols - 2)
  let viewportHeight = max(18, h.rows)
  let innerWidth = max(10, h.cols - 4)
  result = ui(r):
    tdiv(class = "multiple-borders-port"):
      buildBordersStack(r, width, viewportHeight, innerWidth)
