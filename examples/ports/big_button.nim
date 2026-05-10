## examples/ports/big_button.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/big_button.py` (M23 compat suite).
##
## Original (Python):
##
##   class ButtonApp(App):
##       CSS = """
##       Button {
##           height: 9;
##       }
##       """
##       def compose(self) -> ComposeResult:
##           yield Button("Hello")
##           yield Button("Hello\nWorld !!")
##
## Two stacked buttons, both at a tall fixed height (CSS `height: 9`).
## isonim-tui's M12 button auto-sizes vertically to its label rows;
## we don't have a CSS height override on the button widget API yet,
## so the rendered height differs from Textual's (a documented
## visual divergence — captured as a known gap in the README).
## The second button has a multi-line label; the cell-content matches.
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Both buttons use the existing handler-less
## `wButton(label, width)` overload.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildBigButtonApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let width = max(20, h.cols div 2)

  result = ui(r):
    tdiv(class = "big-button-port"):
      wButton(r, "Hello", width)
      wButton(r, "Hello\nWorld !!", width)
