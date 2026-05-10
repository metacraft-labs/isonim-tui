## examples/ports/toggle_style_order.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/toggle_style_order.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class CheckboxApp(App):
##       CSS = """
##       Checkbox > .toggle--label, Label {
##           color: white;
##           text-opacity: 50%;
##       }
##       """
##       def compose(self):
##           yield Checkbox("[red bold]This is just[/] some text.")
##           yield Label("[bold red]This is just[/] some text.")
##
## A Checkbox + Label pair that share the same opacity-modulated style.
## Markup interpretation isn't on the M11/M12 widget label path so
## the bracket sequences render literally — see the README's gap log.
## Cell-content remains stable so the snapshot stays reliable.
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The Checkbox composes via the new `wCheckbox`
## wrapper. The Label needs a post-construction `setStyle("color",
## "white")` (the CSS override path), so it's built outside the `ui()`
## block and embedded via `embedNode` (mirrors DM-M3's
## `placeholder_disabled` "needs the node before mounting" precedent).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildStyledLabelNode(r: TerminalRenderer; text: string;
                          width: int): TerminalNode =
  ## Build a Label and stamp `color: white` on it so the rendered cells
  ## carry the styled-foreground colour. The setStyle call can't live
  ## inside the `ui()` block (it'd need the node before it's appended),
  ## so the whole thing is built here and returned for the DSL to embed.
  let lab = newLabel(r, text, width)
  r.setStyle(lab.node, "color", "white")
  lab.node

proc buildToggleStyleOrderApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let labelWidth = max(20, h.cols - 2)

  result = ui(r):
    tdiv(class = "toggle-style-order-port"):
      wCheckbox(r, "[red bold]This is just[/] some text.",
                false, false, "white")
      buildStyledLabelNode(r, "[bold red]This is just[/] some text.",
                           labelWidth)
