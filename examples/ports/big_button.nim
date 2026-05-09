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

import isonim_tui

proc buildBigButtonApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let b1 = newButton(r, "Hello", width = max(20, h.cols div 2))
  let b2 = newButton(r, "Hello\nWorld !!", width = max(20, h.cols div 2))
  r.appendChild(root, b1.node)
  r.appendChild(root, b2.node)
  root
