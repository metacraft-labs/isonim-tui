## widgets/progress_bar.nim — Tier-3e `ProgressBar` widget (M21).
##
## Port of `textual/widgets/_progress_bar.py` (~385 LOC). Renders a
## horizontal bar that visually fills as `progress / total` advances
## from 0 to 1. The bar is animated via the M7 animator: callers say
## "go from current to N over D ms" and the animator drives sub-cell
## fractional updates. The renderer turns each fractional value into
## a cell-aware glyph (eighth-block fill characters for sub-cell
## precision) so 0..1 progress lerps smoothly even at small widths.
##
## *Indeterminate state*: when `total <= 0` (or `progress` is `nan`),
## the widget runs a marquee bouncing block to signal "work is in
## progress, length unknown". Callers can also fix `progress` and
## flip `total` later — the bar updates on every state change.
##
## Charter §1: every public type is a value object; the widget handle
## itself is a `ref`.

import std/[math, strutils]

import ../renderer
import ../animation/easing
import ../animation/animator
import ../testing/harness

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

const EighthBlocks* = [
  "",        # 0/8
  "\xE2\x96\x8F",  # ▏ 1/8
  "\xE2\x96\x8E",  # ▎ 2/8
  "\xE2\x96\x8D",  # ▍ 3/8
  "\xE2\x96\x8C",  # ▌ 4/8
  "\xE2\x96\x8B",  # ▋ 5/8
  "\xE2\x96\x8A",  # ▊ 6/8
  "\xE2\x96\x89",  # ▉ 7/8
]

const FullBlock* = "\xE2\x96\x88" # █

type
  ProgressBarWidget* = ref object
    h*: TerminalTestHarness
    node*: TerminalNode
    progress*: float64        ## Current progress in [0, total].
    total*: float64           ## Target total. <= 0 = indeterminate.
    width*: int               ## Bar inner width (cells reserved for the
                              ## bar; not counting any percentage label).
    showPercent*: bool        ## Append a "  XX%" suffix when true.
    barColor*: string         ## Foreground colour for the filled portion.
    completeColor*: string    ## Foreground colour at 100%.
    bgColor*: string          ## Foreground colour for the empty trough.
    indeterminateOffset*: float64

# ----------------------------------------------------------------------------
# Forward decls
# ----------------------------------------------------------------------------
proc renderTree*(pb: ProgressBarWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "") =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc isIndeterminate*(pb: ProgressBarWidget): bool {.inline.} =
  pb.total <= 0.0 or classify(pb.progress) in {fcNan}

proc clampedProgress*(pb: ProgressBarWidget): float64 =
  ## Returns `progress / total` clamped to [0, 1]. NaN-safe.
  if pb.total <= 0.0: return 0.0
  let raw = pb.progress / pb.total
  if classify(raw) in {fcNan, fcNegInf}: return 0.0
  if classify(raw) == fcInf: return 1.0
  if raw < 0.0: return 0.0
  if raw > 1.0: return 1.0
  raw

proc percentageInt*(pb: ProgressBarWidget): int =
  ## Integer percent in [0, 100], truncated. `0` for indeterminate.
  if pb.isIndeterminate: return 0
  int(pb.clampedProgress * 100.0 + 0.5)

proc fillString(width: int; ratio: float64): string =
  ## Build a `width`-cell string visualising `ratio` in [0, 1] using
  ## eighth-block sub-cell precision.
  if width <= 0: return ""
  let totalEighths = width * 8
  let filled = int(round(ratio * totalEighths.float64))
  let fullCells = filled div 8
  let remainder = filled mod 8
  let drawnCells =
    if remainder > 0 and fullCells < width: fullCells + 1
    else: fullCells
  result = ""
  for _ in 0 ..< fullCells:
    result.add FullBlock
  if remainder > 0 and fullCells < width:
    result.add EighthBlocks[remainder]
  for _ in drawnCells ..< width:
    result.add ' '

proc indeterminateString(width: int; offset: float64): string =
  ## Draw a 4-cell bouncing block that rides up and down across the
  ## bar. `offset` is the animated phase in [0, 1).
  if width <= 0: return ""
  let blockWidth = max(1, width div 4)
  let span = max(1, width - blockWidth)
  let phase = (offset mod 1.0)
  let ramp =
    if phase < 0.5: phase * 2.0
    else: (1.0 - phase) * 2.0
  let leftCell = int(ramp * span.float64 + 0.5)
  result = newStringOfCap(width)
  for i in 0 ..< width:
    if i >= leftCell and i < leftCell + blockWidth:
      result.add FullBlock
    else:
      result.add ' '

proc renderTree*(pb: ProgressBarWidget) =
  let r = pb.h.renderer
  clearTreeChildren(r, pb.node)
  let bar =
    if pb.isIndeterminate: indeterminateString(pb.width, pb.indeterminateOffset)
    else: fillString(pb.width, pb.clampedProgress)
  let useColor =
    if pb.isIndeterminate: pb.barColor
    elif pb.clampedProgress >= 1.0 - 1e-9: pb.completeColor
    else: pb.barColor
  let line =
    if pb.showPercent and not pb.isIndeterminate:
      bar & "  " & align($pb.percentageInt, 3, ' ') & "%"
    else:
      bar
  emitRow(r, pb.node, line, useColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newProgressBar*(h: TerminalTestHarness;
                     total: float64 = 100.0;
                     progress: float64 = 0.0;
                     width: int = 30;
                     showPercent: bool = true;
                     barColor: string = "blue";
                     completeColor: string = "green";
                     bgColor: string = ""): ProgressBarWidget =
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "progress-bar")
  r.setAttribute(node, "class", "progress-bar")
  let pb = ProgressBarWidget(
    h: h, node: node,
    progress: progress, total: total,
    width: max(1, width),
    showPercent: showPercent,
    barColor: barColor, completeColor: completeColor, bgColor: bgColor,
    indeterminateOffset: 0.0)
  pb.renderTree()
  pb

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc setProgress*(pb: ProgressBarWidget; value: float64) =
  pb.progress = value
  pb.renderTree()

proc setTotal*(pb: ProgressBarWidget; value: float64) =
  pb.total = value
  pb.renderTree()

proc advance*(pb: ProgressBarWidget; delta: float64) =
  pb.progress += delta
  pb.renderTree()

# ----------------------------------------------------------------------------
# Animation: bind to M7 animator
# ----------------------------------------------------------------------------

proc animateTo*(pb: ProgressBarWidget;
                target: float64;
                durationMs: float64;
                easingFn: EasingFunction = easeLinear;
                onComplete: AnimationCompleteProc = nil) =
  ## Drive `progress` from its current value to `target` over
  ## `durationMs` virtual milliseconds, using the supplied easing curve
  ## (defaults to linear). Each animator tick rebuilds the visible
  ## tree; the harness's `flush` re-emits the cell diff.
  let captured = pb
  pb.h.animator.animateFloat(
    targetId = pb.node.id,
    attribute = "progress",
    startValue = pb.progress,
    endValue = target,
    durationMs = durationMs,
    easingFn = easingFn,
    setter = proc(v: float64) =
      captured.progress = v
      captured.renderTree()
      captured.h.flush(),
    onComplete = onComplete)

proc startIndeterminateAnimation*(pb: ProgressBarWidget;
                                  cycleMs: float64 = 1500.0) =
  ## Begin a self-resetting marquee animation for the indeterminate
  ## state. Each cycle ramps `indeterminateOffset` from 0 to 1 over
  ## `cycleMs`, then restarts. Callers stop it by calling
  ## `setTotal(...)` with a positive value (the next render will pick
  ## the determinate path) or by calling `cancelIndeterminate`.
  let captured = pb
  pb.h.animator.animateFloat(
    targetId = pb.node.id,
    attribute = "indeterminate",
    startValue = 0.0,
    endValue = 1.0,
    durationMs = cycleMs,
    easingFn = easeLinear,
    setter = proc(v: float64) =
      captured.indeterminateOffset = v
      captured.renderTree()
      captured.h.flush(),
    onComplete = proc() =
      # Loop while still indeterminate.
      if captured.isIndeterminate:
        captured.startIndeterminateAnimation(cycleMs))

proc cancelIndeterminate*(pb: ProgressBarWidget) =
  pb.h.animator.cancel(pb.node.id, "indeterminate")

proc id*(pb: ProgressBarWidget): int {.inline.} = pb.node.id
