## examples/ports/button_outline.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/button_outline.py` (M23 compat suite).
##
## Original (Python):
##
##   class ButtonIssue(App[None]):
##       AUTO_FOCUS = None
##       CSS = """
##       Button {
##           outline: white;
##       }
##       """
##       def compose(self) -> ComposeResult:
##           yield Button("Test")
##
## A single un-focused, un-styled (default-variant) button with a white
## outline. The `outline:` property in Textual paints a one-cell band
## *outside* the border — isonim-tui's M11 border renderer paints the
## border ring; `outline-color` is a thin overlay handled by the M5
## cascade. We model the outline by setting the border colour to
## `white` so the cell-content of the snapshot matches what Textual
## emits at this terminal size.
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The styled-button surface (variant / border
## / borderColor / disabled) is reachable through the DM-M3-added
## `wButtonStyled` wrapper; we go through that wrapper so the
## border-row glyphs themselves are painted with the requested
## colour. (An earlier draft used `r.setStyle(btn.node,
## "border-color", "white")` to route the colour through the M5
## cascade instead — that path produces a different cell-content
## golden than the wrapper because the cascade fills the
## `border-color` property rather than colouring the rendered border
## glyphs. The recorded golden was re-recorded for the wrapper path
## as part of DM-M3.)

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildButtonOutlineApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "button-outline-port"):
      wButtonStyled(r, "Test", 12, bvDefault, bsRound, "white", false, nil)
