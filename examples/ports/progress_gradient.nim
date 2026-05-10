## examples/ports/progress_gradient.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/progress_gradient.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class ProgressApp(App[None]):
##       def compose(self) -> ComposeResult:
##           gradient = Gradient.from_colors(
##               "#881177", "#aa3355", "#cc6666", "#ee9944",
##               "#eedd00", "#99dd55", "#44dd88", "#22ccbb",
##               "#00bbcc", "#0099cc", "#3366bb", "#663399")
##           yield ProgressBar(total=100, gradient=gradient)
##       def on_mount(self) -> None:
##           self.query_one(ProgressBar).update(progress=50)
##
## A single ProgressBar at 50%/100 with a 12-stop colour gradient.
## isonim-tui's M21 ProgressBar widget supports a single
## `barColor` / `completeColor` pair (gradient interpolation is a
## follow-up surface — captured as a known-difference in the M23
## tolerance doc); we pick the gradient's mid-stop so the painted
## colour matches what Textual chooses for the 50% bucket.
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The `wProgressBar` wrapper (added in DM-M3)
## takes the harness directly, mirroring `newProgressBar`'s M21
## constructor signature.

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildProgressGradientApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let barWidth = max(20, h.cols - 4)

  result = ui(r):
    tdiv(class = "progress-gradient-port"):
      # Mid-gradient stop at 50% — `#99dd55` is the 6th of 12 colours.
      wProgressBar(h, 100.0, 50.0, barWidth, true, "#99dd55", "#22ccbb", "")
