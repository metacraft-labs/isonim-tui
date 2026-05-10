## examples/ports/loading_indicator_demo.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's `loading_indicator.py`-class apps. Three
## `LoadingIndicator` widgets with different labels stacked vertically.
## The animation phase is fixed (frame 0) so the snapshot stays
## deterministic.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const IndicatorLabels = ["loading", "saving", "uploading"]

proc buildIndicatorStack(r: TerminalRenderer;
                         width, viewportHeight: int): TerminalNode =
  ## Build a vertical `Container` with one `LoadingIndicator` per
  ## label. Returns the container's `.node` for the DSL to embed.
  let outer = newContainer(r, width = width,
                           viewportHeight = viewportHeight,
                           layout = clVertical)
  for label in IndicatorLabels:
    let li = newLoadingIndicator(r, label = label, color = "cyan")
    outer.append(li.node)
  outer.node

proc buildLoadingIndicatorDemoApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "loading-indicator-demo-port"):
      buildIndicatorStack(r, h.cols, h.rows)
