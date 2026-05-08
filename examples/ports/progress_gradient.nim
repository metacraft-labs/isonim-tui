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

import isonim_tui

proc buildProgressGradientApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  # Mid-gradient stop at 50% — `#99dd55` is the 6th of 12 colours.
  # M11 progress bar takes the harness directly (M15 / M21 refactor).
  let pb = newProgressBar(h, total = 100.0, progress = 50.0,
                          width = max(20, h.cols - 4),
                          showPercent = true,
                          barColor = "#99dd55",
                          completeColor = "#22ccbb")
  r.appendChild(root, pb.node)

  root
