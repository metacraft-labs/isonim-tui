## examples/ports/button_widths.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/button_widths.py` (M23 compat suite).
##
## Original (Python):
##
##   class HorizontalWidthAutoApp(App[None]):
##       CSS = """
##       Horizontal {
##           border: solid red;
##           height: auto;
##           width: auto;
##       }
##       """
##       def compose(self) -> ComposeResult:
##           with Horizontal(classes="auto"):
##               yield Button("This is a very wide button")
##           with Horizontal(classes="auto"):
##               yield Button("This is a very wide button")
##               yield Button("This is a very wide button")
##
## Auto-width horizontal containers wrapping one or two wide buttons.
## We use M11 `Container` widgets in horizontal layout with red
## solid borders.
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The Container widget needs the widget
## *object* (to call `.append(child.node)`), so each row is built
## outside the `ui()` block by a small helper that returns the
## container's `.node` for the DSL to embed (mirrors DM-M2's
## `log_viewer.buildRichLogNode` precedent).

import isonim_tui
import isonim/dsl/ui

const ButtonLabel = "This is a very wide button"
const BtnInner = ButtonLabel.len + 4   ## Button auto-size: label + 4 padding.
const BtnOuter = BtnInner + 2          ## Button outer width: inner + 2 borders.

proc buildHorizontalRow(r: TerminalRenderer; width: int;
                        buttonCount: int): TerminalNode =
  ## Build a horizontal `Container` with `buttonCount` wide buttons.
  ## The container needs the widget object to call `.append`, so it's
  ## constructed here outside the `ui()` block; the returned `.node`
  ## is what the DSL embeds.
  let row = newContainer(r, width = width, viewportHeight = 3,
                         border = bsSolid, borderColor = "red",
                         layout = clHorizontal)
  for _ in 0 ..< buttonCount:
    let btn = newButton(r, ButtonLabel)
    row.append(btn.node)
  row.node

proc buildButtonWidthsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let row1Width = BtnOuter + 2          # +2 for the container's border.
  let row2Width = BtnOuter * 2 + 2

  result = ui(r):
    tdiv(class = "button-widths-port"):
      buildHorizontalRow(r, row1Width, 1)
      buildHorizontalRow(r, row2Width, 2)
