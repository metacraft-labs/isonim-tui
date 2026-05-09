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

import isonim_tui

proc buildToggleStyleOrderApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let cb = newCheckbox(r, label = "[red bold]This is just[/] some text.",
                       color = "white")
  r.appendChild(root, cb.node)

  let lab = newLabel(r, "[bold red]This is just[/] some text.",
                     width = max(20, h.cols - 2))
  r.setStyle(lab.node, "color", "white")
  r.appendChild(root, lab.node)
  root
