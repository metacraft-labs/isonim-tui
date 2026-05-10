## examples/ports/header_with_title.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's `header_screen.py` snapshot pattern: a `Header`
## widget with a configured title + subtitle + icon. Captures the
## three-section header chrome (icon-left / title-centre / clock-right)
## in one frame.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Reuses the existing `wHeader` wrapper.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildHeaderWithTitleApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "header-with-title-port"):
      wHeader(r, "M23 Compat", "batch 3", h.cols, false)
