## examples/ports/multiple_borders.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `border-styles` snapshot apps that demonstrate
## the suite of `border` styles applied to a widget. We mount one
## `Static` per BorderStyle in a vertical Container so the snapshot
## captures every glyph variant in one frame.
##
## Originally each Static was mounted directly under the root (Batch-3
## workaround) because `renderVertical` only consumed the first text
## row of each direct child. The vertical-multi-row fix that landed
## alongside the renderHorizontal fix retired that workaround;
## bordered Statics now survive nesting inside a Container.

import isonim_tui

const StyleSamples* = [
  bsSolid, bsDashed, bsDouble, bsHeavy, bsAscii, bsRound]

proc buildMultipleBordersApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  # Sum of bordered heights = 6 * (1 + 2) = 18 rows. Use an
  # 18-row inner viewport so every variant lands in the snapshot.
  let outer = newContainer(r,
    width = max(36, h.cols - 2),
    viewportHeight = max(18, h.rows),
    layout = clVertical)
  for style in StyleSamples:
    let s = newStatic(r, $style, width = max(10, h.cols - 4),
                      height = 1, border = style)
    outer.append(s.node)
  r.appendChild(root, outer.node)
  root
