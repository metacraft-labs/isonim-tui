## examples/ports/button_multiline_label.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/button_multiline_label.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class ButtonWithMultilineLabelApp(App):
##       def compose(self) -> ComposeResult:
##           yield Button("Button\nwith\nmulti-line\nlabel")
##
## A single button whose label contains literal `\n` separators —
## Textual paints each line on its own row, expanding the button's
## height. isonim-tui's M12 button uses the label verbatim; we wrap
## the label in a `Container` sized to fit so the snapshot has
## predictable bounds.

import std/strutils
import isonim_tui

proc buildButtonMultilineLabelApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let label = "Button\nwith\nmulti-line\nlabel"
  # Width = max line width + 4 (Textual's default left/right padding).
  var maxCells = 0
  for line in label.split('\n'):
    if cellWidth(line) > maxCells: maxCells = cellWidth(line)
  let btn = newButton(r, label, width = maxCells + 4)
  r.appendChild(root, btn.node)
  root
