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
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The button uses the existing handler-less
## `wButton` overload (label + width).

import std/strutils
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildButtonMultilineLabelApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let label = "Button\nwith\nmulti-line\nlabel"
  # Width = max line width + 4 (Textual's default left/right padding).
  var maxCells = 0
  for line in label.split('\n'):
    if cellWidth(line) > maxCells: maxCells = cellWidth(line)
  let width = maxCells + 4

  result = ui(r):
    tdiv(class = "button-multiline-label-port"):
      wButton(r, label, width)
