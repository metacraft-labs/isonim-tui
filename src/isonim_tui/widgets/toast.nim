## widgets/toast.nim — Tier-2 `Toast` widget (M14).
##
## Port of `textual/widgets/toast.py` (~206 LOC). A short-lived
## notification that auto-dismisses after `durationMs` (default
## 5,000 ms) of virtual time. The auto-dismiss schedules a clock
## callback that pops the toast off the layer and removes it from the
## tree; on real wall-clock time this means "5 seconds later, the
## toast disappears", on a TestClock it means "h.advance(5000)
## clears the toast".
##
## Toasts are rendered on a high overlay layer (default 5) so they
## sit above modals' content but below any always-on focus indicator.
##
## Charter §1: every public type is a value object; the toast handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ../css/properties
import ../animation/easing
import ../animation/animator
import ../testing/harness
import isonim/core/clock
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  ToastSeverity* = enum
    tsInformation
    tsWarning
    tsError

  ToastState* = enum
    tstHidden
    tstEntering
    tstVisible
    tstExiting

  ToastWidget* = ref object
    h*: TerminalTestHarness
    node*: TerminalNode
    title*: string
    body*: string
    severity*: ToastSeverity
    width*: int
    layer*: int
    durationMs*: float64              ## Visible time before auto-dismiss.
    state*: ToastState
    progress*: float64                ## 0..1 entry/exit ramp.
    onDismiss*: proc()

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(t: ToastWidget)
proc show*(t: ToastWidget)
proc dismiss*(t: ToastWidget)

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

proc severityColor(sev: ToastSeverity): string =
  case sev
  of tsInformation: "blue"
  of tsWarning:     "yellow"
  of tsError:       "red"

proc renderTree*(t: ToastWidget) =
  let r = t.h.renderer
  clearTreeChildren(r, t.node)
  let glyphs = bordersGlyphs(bsRound)
  let color = severityColor(t.severity)
  r.setStyle(t.node, "layer", $t.layer)
  r.setStyle(t.node, "background-color", color)

  let visible = t.state in {tstEntering, tstVisible, tstExiting}
  if not visible: return

  emitRow(r, t.node, topBorderRow(glyphs, t.width - 2), color)
  let titleBody = padOrTruncate(t.title, t.width - 2)
  emitRow(r, t.node, glyphs.left & titleBody & glyphs.right, color)
  let textBody = padOrTruncate(t.body, t.width - 2)
  emitRow(r, t.node, glyphs.left & textBody & glyphs.right, color)
  emitRow(r, t.node, bottomBorderRow(glyphs, t.width - 2), color)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newToast*(h: TerminalTestHarness;
               title: string;
               body: string = "";
               severity: ToastSeverity = tsInformation;
               width: int = 30;
               layer: int = 5;
               durationMs: float64 = 5000.0;
               onDismiss: proc() = nil): ToastWidget =
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "toast")
  r.setAttribute(node, "class", "toast")
  ToastWidget(
    h: h, node: node, title: title, body: body,
    severity: severity, width: max(8, width),
    layer: layer, durationMs: durationMs,
    state: tstHidden, progress: 0.0,
    onDismiss: onDismiss)

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc scheduleAutoDismiss(t: ToastWidget) =
  ## Use the harness's TestClock to schedule the dismiss callback in
  ## `durationMs` virtual milliseconds.
  let captured = t
  discard t.h.clock.schedule(proc() = captured.dismiss(),
                             t.durationMs)

proc show*(t: ToastWidget) =
  if t.state in {tstEntering, tstVisible}: return
  t.state = tstEntering
  t.progress = 0.0
  if t.h.root != nil:
    t.h.renderer.appendChild(t.h.root, t.node)
  t.renderTree()
  t.h.flush()
  # Brief 200ms entry animation; on completion -> tstVisible and
  # schedule auto-dismiss.
  t.h.animator.animateFloat(
    targetId = t.node.id,
    attribute = "toast-enter",
    startValue = 0.0,
    endValue = 1.0,
    durationMs = 200.0,
    easingFn = easeOutCubic,
    setter = proc(v: float64) =
      t.progress = v
      t.h.flush(),
    onComplete = proc() =
      t.state = tstVisible
      t.progress = 1.0
      t.renderTree()
      t.h.flush()
      t.scheduleAutoDismiss())

proc dismiss*(t: ToastWidget) =
  if t.state in {tstHidden, tstExiting}: return
  t.state = tstExiting
  t.h.animator.animateFloat(
    targetId = t.node.id,
    attribute = "toast-exit",
    startValue = 1.0,
    endValue = 0.0,
    durationMs = 200.0,
    easingFn = easeOutCubic,
    setter = proc(v: float64) =
      t.progress = v
      t.h.flush(),
    onComplete = proc() =
      t.state = tstHidden
      if t.h.root != nil and t.node.parent != nil:
        t.h.renderer.removeChild(t.h.root, t.node)
      t.renderTree()
      if t.onDismiss != nil: t.onDismiss()
      t.h.flush())

proc isVisible*(t: ToastWidget): bool {.inline.} =
  t.state in {tstEntering, tstVisible, tstExiting}

proc id*(t: ToastWidget): int {.inline.} = t.node.id
