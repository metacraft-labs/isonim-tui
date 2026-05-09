## examples/ports/progress_bar_states.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's various progress-bar snapshot apps. We mount
## five `ProgressBar` widgets at 0 / 25 / 50 / 75 / 100 % to capture
## the bar's full visual range in one frame.

import isonim_tui

proc buildProgressBarStatesApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let outer = newContainer(r, width = h.cols, viewportHeight = h.rows,
                           layout = clVertical)
  for pct in [0.0, 25.0, 50.0, 75.0, 100.0]:
    let pb = newProgressBar(h, total = 100.0, progress = pct,
                            width = max(20, h.cols - 4),
                            showPercent = true,
                            barColor = "blue",
                            completeColor = "green")
    outer.append(pb.node)
  r.appendChild(root, outer.node)
  root
