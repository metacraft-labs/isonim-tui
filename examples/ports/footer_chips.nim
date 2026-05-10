## examples/ports/footer_chips.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's footer-chip snapshot apps: a `Footer` widget with
## several keyboard-binding entries rendered as chips along the bottom
## of the screen.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Reuses the existing `wFooter` wrapper.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

const FooterBindings = [
  FooterBinding(key: "q", description: "Quit"),
  FooterBinding(key: "s", description: "Save"),
  FooterBinding(key: "o", description: "Open"),
  FooterBinding(key: "?", description: "Help")]

proc buildFooterChipsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "footer-chips-port"):
      wFooter(r, FooterBindings, h.cols, true)
