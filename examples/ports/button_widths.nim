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

import isonim_tui

proc buildButtonWidthsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let label = "This is a very wide button"
  let btnInner = label.len + 4   # Button auto-size: label + 4 padding.
  let btnOuter = btnInner + 2    # Button outer width: inner + 2 borders.

  # First horizontal — one button.
  let row1Width = btnOuter + 2   # +2 for the container's border.
  let h1 = newContainer(r, width = row1Width, viewportHeight = 3,
                        border = bsSolid, borderColor = "red",
                        layout = clHorizontal)
  let b1 = newButton(r, label)
  h1.append(b1.node)
  r.appendChild(root, h1.node)

  # Second horizontal — two buttons side by side.
  let row2Width = btnOuter * 2 + 2
  let h2 = newContainer(r, width = row2Width, viewportHeight = 3,
                        border = bsSolid, borderColor = "red",
                        layout = clHorizontal)
  let b2a = newButton(r, label)
  let b2b = newButton(r, label)
  h2.append(b2a.node)
  h2.append(b2b.node)
  r.appendChild(root, h2.node)

  root
