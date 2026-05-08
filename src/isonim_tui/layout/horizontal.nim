## Horizontal-stack layout policy.
##
## Port of Textual's `textual/layouts/horizontal.py`. Lays children out
## left-to-right, full parent height. Yoga `flex-direction: row` with
## each child stretched across the cross axis.

import isonim/layout/layout_engine
import ./terminal_layout

type
  HorizontalLayout* = object
    gap*: int     ## Cells of gap between children. 0 = no gap.

proc newHorizontal*(gap: int = 0): HorizontalLayout {.inline.} =
  HorizontalLayout(gap: gap)

proc apply*(layout: TerminalLayout; container: int64;
            policy: HorizontalLayout) =
  ## Configure `container` to lay out its children horizontally with the
  ## given gap.
  layout.engine.setLayoutStyle(container, "flex-direction", "row")
  layout.engine.setLayoutStyle(container, "align-items", "stretch")
  if policy.gap > 0:
    layout.engine.setLayoutStyle(container, "gap", $policy.gap)
