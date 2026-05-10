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
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The first two buttons use the simple
## handler-less `wButton(label, width)` overload; the third needs
## `wButtonStyled` so the `disabled = true` flag is reachable
## positionally.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildButtonMarkupApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "button-markup-port"):
      wButton(r, "[italic red]Focused[/] Button", 0)
      wButton(r, "[italic red]Blurred[/] Button", 0)
      wButtonStyled(r, "[italic red]Disabled[/] Button", 0,
                    bvDefault, bsRound, "", true, nil)
