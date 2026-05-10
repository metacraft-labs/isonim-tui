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
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The Static widget composes cleanly via the
## existing `wStatic` wrapper.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildViewportUnitsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  # `100vw / 100vh` → resolve against the harness's terminal grid.
  # Subtract 2 cells for the border ring (Static counts inner content).
  let width = max(2, h.cols - 2)
  let height = max(1, h.rows - 2)

  result = ui(r):
    tdiv(class = "viewport-units-port"):
      wStatic(r, "Hello, world!", width, height, bsSolid, "cyan", false)
