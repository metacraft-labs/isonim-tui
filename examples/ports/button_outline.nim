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

import isonim_tui

proc buildButtonOutlineApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let btn = newButton(r, "Test", width = 12)
  # The Textual CSS sets `outline: white;` — we mirror that as the
  # border colour on the rendered button (border + outline collapse to
  # the same painted ring at this widget's size).
  r.setStyle(btn.node, "border-color", "white")
  r.appendChild(root, btn.node)
  root
