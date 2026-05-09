## examples/ports/loading_indicator_demo.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `loading_indicator.py`-class apps. We mount
## three `LoadingIndicator` widgets with different labels stacked
## vertically. The animation phase is fixed (frame 0) so the snapshot
## stays deterministic.

import isonim_tui

proc buildLoadingIndicatorDemoApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let outer = newContainer(r, width = h.cols, viewportHeight = h.rows,
                           layout = clVertical)
  for label in ["loading", "saving", "uploading"]:
    let li = newLoadingIndicator(r, label = label, color = "cyan")
    outer.append(li.node)
  r.appendChild(root, outer.node)
  root
