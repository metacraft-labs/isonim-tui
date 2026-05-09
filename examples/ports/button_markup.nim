## examples/ports/button_markup.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/button_markup.py` (M23 compat suite).
##
## Original (Python):
##
##   class ButtonsWithMarkupApp(App):
##       def compose(self) -> ComposeResult:
##           yield Button("[italic red]Focused[/] Button")
##           yield Button("[italic red]Blurred[/] Button")
##           yield Button("[italic red]Disabled[/] Button", disabled=True)
##
## Three buttons whose labels carry rich-style markup. M12's button
## takes a plain string label (M11/M12 doesn't yet plumb the rich-text
## `Content` overload through to button labels) — we render the
## bracketed source so the cell-content remains stable. The visual
## divergence (markup not interpreted) is documented as a follow-up
## gap in `examples/ports/README.md`. The third button is `disabled`.

import isonim_tui

proc buildButtonMarkupApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let b1 = newButton(r, "[italic red]Focused[/] Button")
  let b2 = newButton(r, "[italic red]Blurred[/] Button")
  let b3 = newButton(r, "[italic red]Disabled[/] Button",
                    disabled = true)
  r.appendChild(root, b1.node)
  r.appendChild(root, b2.node)
  r.appendChild(root, b3.node)
  root
