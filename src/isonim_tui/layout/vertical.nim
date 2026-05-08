## Vertical-stack layout policy.
##
## Port of Textual's `textual/layouts/vertical.py`. The semantics are
## "lay children out top-to-bottom, full parent width". In Yoga that's
## just `flex-direction: column` (the default) with each child stretched
## across the cross axis.
##
## Charter §1: the policy is a value `object`. Helpers configure the
## underlying `LayoutEngine` (Yoga FFI) — they don't allocate anything
## of their own.

import isonim/layout/layout_engine
import ./terminal_layout

type
  VerticalLayout* = object
    ## Marker type so user code can pass a "vertical layout" record
    ## around without any per-policy allocation. Today this carries no
    ## fields — the policy is fully encoded by Yoga style flags applied
    ## to the container.
    gap*: int     ## Cells of gap between children. 0 = no gap.

proc newVertical*(gap: int = 0): VerticalLayout {.inline.} =
  VerticalLayout(gap: gap)

proc apply*(layout: TerminalLayout; container: int64;
            policy: VerticalLayout) =
  ## Configure `container` to lay out its children vertically using the
  ## given gap.
  layout.engine.setLayoutStyle(container, "flex-direction", "column")
  layout.engine.setLayoutStyle(container, "align-items", "stretch")
  if policy.gap > 0:
    layout.engine.setLayoutStyle(container, "gap", $policy.gap)
