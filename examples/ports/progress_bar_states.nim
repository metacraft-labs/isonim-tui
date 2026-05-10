## examples/ports/progress_bar_states.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's various progress-bar snapshot apps. Five
## `ProgressBar` widgets at 0 / 25 / 50 / 75 / 100 % capture the bar's
## full visual range in one frame.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const PercentSteps = [0.0, 25.0, 50.0, 75.0, 100.0]

proc buildProgressStack(h: TerminalTestHarness; barWidth: int): TerminalNode =
  ## Build a vertical `Container` with one `ProgressBar` per percent
  ## step. ProgressBar requires the harness for animator wiring (M21
  ## contract). Returns the container's `.node` for the DSL to embed.
  let r = h.renderer
  let outer = newContainer(r, width = h.cols, viewportHeight = h.rows,
                           layout = clVertical)
  for pct in PercentSteps:
    let pb = newProgressBar(h, total = 100.0, progress = pct,
                            width = barWidth,
                            showPercent = true,
                            barColor = "blue",
                            completeColor = "green")
    outer.append(pb.node)
  outer.node

proc buildProgressBarStatesApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let barWidth = max(20, h.cols - 4)
  result = ui(r):
    tdiv(class = "progress-bar-states-port"):
      buildProgressStack(h, barWidth)
