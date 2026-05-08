## test_animation_cancellation
##
## M7: starting an animation and cancelling it mid-way must:
##   1. Freeze the value at its mid-flight point (no further mutation).
##   2. NOT call the on_complete callback.
##   3. Remove the animation from the active set.

import std/math
import unittest
import isonim_tui

const Tolerance = 1e-9

suite "M7: animation cancellation":
  test "test_animation_cancellation":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var observed: seq[float64] = @[]
    var completedCount = 0

    let targetId = 42
    let attribute = "scroll_y"
    let setter = proc (v: float64) {.closure.} = observed.add v
    let onDone = proc () {.closure.} = inc completedCount
    h.animator.animateFloat(
      targetId = targetId,
      attribute = attribute,
      startValue = 0.0,
      endValue = 200.0,
      durationMs = 1000.0,
      easingFn = easeLinear,
      setter = setter,
      onComplete = onDone)

    check h.animator.isAnimating(targetId, attribute)

    # Drive ~250 ms (one quarter of the way).
    h.advanceMs(250.0)
    let valueAtCancel = (if observed.len > 0: observed[^1] else: 0.0)
    # Linear progression: roughly 50 at the 250 ms point.
    check valueAtCancel > 30.0
    check valueAtCancel < 70.0

    let observedLen = observed.len

    # Cancel.
    h.animator.cancel(targetId, attribute)
    check not h.animator.isAnimating(targetId, attribute)

    # Drive much further; nothing should mutate.
    h.advanceMs(2000.0)

    check observed.len == observedLen
    check abs(observed[^1] - valueAtCancel) <= Tolerance
    check completedCount == 0
    check h.animator.activeCount == 0

    h.dispose()

  test "test_cancel_unknown_animation_is_noop":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    h.animator.cancel(99, "nope")  # must not raise
    check h.animator.activeCount == 0
    h.dispose()

  test "test_cancel_all_clears_active_set":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var fired = 0
    h.animator.animateFloat(
      targetId = 1, attribute = "a",
      startValue = 0.0, endValue = 1.0, durationMs = 100.0,
      easingFn = easeLinear,
      setter = proc (v: float64) {.closure.} = discard,
      onComplete = proc () {.closure.} = inc fired)
    h.animator.animateFloat(
      targetId = 2, attribute = "b",
      startValue = 0.0, endValue = 1.0, durationMs = 100.0,
      easingFn = easeLinear,
      setter = proc (v: float64) {.closure.} = discard,
      onComplete = proc () {.closure.} = inc fired)

    check h.animator.activeCount == 2
    h.animator.cancelAll()
    check h.animator.activeCount == 0

    h.advanceMs(200.0)
    check fired == 0
    h.dispose()
