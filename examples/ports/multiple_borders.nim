## examples/ports/multiple_borders.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `border-styles` snapshot apps that demonstrate
## the suite of `border` styles applied to a widget. We mount one
## `Static` per BorderStyle in a vertical Container so the snapshot
## captures every glyph variant in one frame.

import isonim_tui

const StyleSamples* = [
  bsSolid, bsDashed, bsDouble, bsHeavy, bsAscii, bsRound]

proc buildMultipleBordersApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  # Mount each Static directly under the root so its top/body/bottom
  # border rows survive — M11's vertical Container only consumes the
  # first row of each child today (tracked as a follow-up).
  for style in StyleSamples:
    let s = newStatic(r, $style, width = max(10, h.cols - 4),
                      height = 1, border = style)
    r.appendChild(root, s.node)
  root
