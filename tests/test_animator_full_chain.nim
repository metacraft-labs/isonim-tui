## test_animator_full_chain
##
## M7: animate a widget's `offset.x` from 0 to 100 over 250 ms with
## `in_out_cubic`. Step the virtual clock at 60 Hz; assert the value
## at t=125 ms matches the cubic midpoint.
##
## "Full chain" means the test goes through the *real* animator, the
## *real* test clock, the *real* harness flush. The animation `setter`
## writes into a captured float that the test inspects after each
## frame.

import std/math
import unittest
import isonim_tui
import isonim/core/clock

# In_out_cubic at factor=0.5 is exactly 0.5 by symmetry, so 0..100 at
# t=125ms (the midpoint of a 250ms animation) lands at exactly 50.0.
const ExpectedMidpoint = 50.0
const Tolerance = 1e-9

suite "M7: animator full chain":
  test "test_animator_full_chain":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.appendChild(root, r.createTextNode("animating"))
      root)

    var captured: seq[tuple[t: float64; v: float64]] = @[]

    let targetId = h.findByTag("div")[0].id
    h.animator.animateFloat(
      targetId = targetId,
      attribute = "offset_x",
      startValue = 0.0,
      endValue = 100.0,
      durationMs = 250.0,
      easingFn = easeInOutCubic,
      setter = proc (v: float64) {.closure.} =
        captured.add((h.clock.currentTime, v)))

    # Step at exactly 60 Hz. Use a 16.6667 ms frame interval so the
    # clock lands on the same cadence the animator schedules at.
    let frameMs = 1000.0 / 60.0
    var elapsed = 0.0
    while elapsed < 250.0 + frameMs:
      h.advanceMs(frameMs)
      elapsed += frameMs

    # The animation should be done.
    check h.animator.activeCount == 0

    # Pick the frame that lands at or just past 125 ms.
    var midIdx = -1
    for i, c in captured:
      if c.t >= 125.0:
        midIdx = i
        break
    check midIdx >= 0
    # Sanity: the captured time at midIdx is within one frame of 125 ms.
    check captured[midIdx].t >= 125.0 - 1e-9
    check captured[midIdx].t < 125.0 + frameMs + 1e-9

    # Compute the analytical midpoint at the *exact* captured time
    # (60 Hz won't land exactly on 125ms, so we recompute the expected
    # value at the actually-captured time).
    let factor = min(1.0, captured[midIdx].t / 250.0)
    let want =
      if factor < 0.5: 4.0 * factor * factor * factor * 100.0
      else: (1.0 - pow(-2.0 * factor + 2.0, 3.0) / 2.0) * 100.0
    check abs(captured[midIdx].v - want) <= Tolerance

    # First frame: at frame 1 the animator has run one tick. The
    # first captured time should be ~16.667 ms.
    check captured[0].t > 0.0
    check captured[0].t <= frameMs + 1e-9

    # Final captured value should be exactly the destination.
    check abs(captured[^1].v - 100.0) <= Tolerance

    # Verify a precise step lands exactly on the cubic midpoint.
    # Reset and run a second animation that steps to t=125 cleanly.
    let h2 = newTerminalTestHarness(20, 3)
    h2.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    var lastValue = 0.0
    h2.animator.animateFloat(
      targetId = 1, attribute = "offset_x",
      startValue = 0.0, endValue = 100.0,
      durationMs = 250.0,
      easingFn = easeInOutCubic,
      setter = proc (v: float64) {.closure.} =
        lastValue = v)
    # Schedule the animator to tick after exactly 125 ms by feeding
    # 7.5 frames (we deliberately step the clock to land on 125.0).
    h2.advanceMs(125.0)
    # `advanceMs` only fires callbacks scheduled before that time;
    # the animator's frame ticker runs every frameMs (~16.67ms),
    # so we should have several ticks by 125 ms. Tick the animator
    # one more time to read the value at exactly t=125.
    h2.animator.tick()
    # The cubic at factor=0.5 is exactly 0.5, so v should be 50.
    check abs(lastValue - ExpectedMidpoint) <= Tolerance
    h2.dispose()

    h.dispose()

  test "test_animator_completion_callback":
    # The on_complete callback fires exactly once when the animation
    # completes naturally.
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var completed = 0
    var finalValue = 0.0
    h.animator.animateFloat(
      targetId = 1, attribute = "x",
      startValue = 0.0, endValue = 1.0,
      durationMs = 100.0,
      easingFn = easeLinear,
      setter = proc (v: float64) {.closure.} = finalValue = v,
      onComplete = proc () {.closure.} = inc completed)

    # Drive past completion.
    h.advanceMs(200.0)

    check completed == 1
    check abs(finalValue - 1.0) <= Tolerance
    check h.animator.activeCount == 0
    h.dispose()

  test "test_animator_replace_animation_for_same_attribute":
    # Animating the same (target, attr) twice replaces the first.
    # The first animation's on_complete should NOT fire (matches
    # cancel semantics).
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var firstCompleted = 0
    var secondCompleted = 0
    var finalValue = 0.0

    h.animator.animateFloat(
      targetId = 1, attribute = "x",
      startValue = 0.0, endValue = 100.0,
      durationMs = 1000.0,
      easingFn = easeLinear,
      setter = proc (v: float64) {.closure.} = finalValue = v,
      onComplete = proc () {.closure.} = inc firstCompleted)

    h.advanceMs(50.0)  # mid-flight

    # Replace.
    h.animator.animateFloat(
      targetId = 1, attribute = "x",
      startValue = 0.0, endValue = 200.0,
      durationMs = 100.0,
      easingFn = easeLinear,
      setter = proc (v: float64) {.closure.} = finalValue = v,
      onComplete = proc () {.closure.} = inc secondCompleted)

    h.advanceMs(500.0)

    check firstCompleted == 0
    check secondCompleted == 1
    # Final value should be 200 (from the second animation).
    check abs(finalValue - 200.0) <= Tolerance
    h.dispose()
