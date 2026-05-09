## examples/ports/viewport_units.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/viewport_units.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class ViewportUnits(App):
##       CSS = "Static {width: 100vw; height: 100vh; border: solid cyan;}"
##       def compose(self) -> ComposeResult:
##           yield Static("Hello, world!")
##
## A Static widget sized to fill the entire viewport with a cyan
## solid border. The M11 Static widget takes explicit width/height —
## we resolve `100vw / 100vh` against the harness's terminal size at
## build time, which produces the same painted cells as Textual's
## CSS-driven sizing.

import isonim_tui

proc buildViewportUnitsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  # `100vw / 100vh` → resolve against the harness's terminal grid.
  # Subtract 2 cells for the border ring (Static counts inner content).
  let inner = newStatic(r, "Hello, world!",
                        width = max(2, h.cols - 2),
                        height = max(1, h.rows - 2),
                        border = bsSolid,
                        borderColor = "cyan")
  r.appendChild(root, inner.node)
  root
