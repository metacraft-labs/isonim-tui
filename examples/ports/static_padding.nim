## examples/ports/static_padding.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `static_padding.py`-class apps that exercise
## a `Static` rendered at several widths to demonstrate cell padding /
## auto-truncation. We mount three Statics inside a vertical container,
## each at a different inner width, all displaying the same text.
## The widget pads the right edge with spaces — the M11 surface for
## CSS `padding` lands later, so we vary the explicit width instead.

import isonim_tui

proc buildStaticPaddingApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  # Stack three borderless Statics at three different inner widths so
  # the snapshot captures the right-pad behaviour at three columns.
  # The child widgets are mounted directly under the root because
  # M11's vertical Container only consumes the first text row of each
  # child — bordered Statics nested inside a Container would lose
  # their top / bottom border rows in this batch (tracked as a vertical
  # layout follow-up; doesn't block the M23 surface widening here).
  let body = "padded"
  let widths = [10, 20, 30]
  for w in widths:
    let s = newStatic(r, body, width = w, height = 1, border = bsSolid)
    r.appendChild(root, s.node)
  root
