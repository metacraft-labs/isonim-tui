## examples/ports/header_with_title.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's `header_screen.py` snapshot pattern: a `Header`
## widget with a configured title + subtitle + icon. Captures the
## three-section header chrome (icon-left / title-centre / clock-right)
## in one frame.

import isonim_tui

proc buildHeaderWithTitleApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let header = newHeader(r,
    title = "M23 Compat", subtitle = "batch 3",
    width = h.cols, tall = false)
  r.appendChild(root, header.node)
  root
