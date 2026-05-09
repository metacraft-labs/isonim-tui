## examples/ports/static_padding.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `static_padding.py`-class apps that exercise
## a `Static` rendered at several widths to demonstrate cell padding /
## auto-truncation. We mount three bordered Statics inside a vertical
## Container, each at a different inner width, all displaying the same
## text. The widget pads the right edge with spaces — the M11 surface
## for CSS `padding` lands later, so we vary the explicit width
## instead.
##
## Originally the three Statics were mounted directly under the root
## (Batch-3 workaround) because `renderVertical` only consumed the
## first text row of each direct child. The vertical-multi-row fix
## landed alongside the renderHorizontal fix retired that workaround;
## bordered Statics now survive nesting inside a Container.

import isonim_tui

proc buildStaticPaddingApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let body = "padded"
  let widths = [10, 20, 30]
  # Sum of bordered heights = 3 * (1 + 2) = 9 rows. Use a 10-row
  # container so the natural stack fits with one trailing pad row.
  let outer = newContainer(r,
    width = max(34, h.cols - 2),
    viewportHeight = max(10, h.rows),
    layout = clVertical)
  for w in widths:
    let s = newStatic(r, body, width = w, height = 1, border = bsSolid)
    outer.append(s.node)
  r.appendChild(root, outer.node)
  root
