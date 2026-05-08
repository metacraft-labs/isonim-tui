## test_animation_pilot_wait_for_animation
##
## M7: `h.pilot.waitForAnimation()` advances the virtual clock until
## all active animations complete. No real wall-clock sleep occurs.

import std/[monotimes, times]
import unittest
import isonim_tui

const Tolerance = 1e-9

suite "M7: pilot waitForAnimation":
  test "test_animation_pilot_wait_for_animation":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var finalValue = 0.0
    var completed = 0
    let setter = proc (v: float64) {.closure.} = finalValue = v
    let onDone = proc () {.closure.} = inc completed
    h.animator.animateFloat(
      targetId = 1,
      attribute = "x",
      startValue = 0.0,
      endValue = 100.0,
      durationMs = 5_000.0,
      easingFn = easeLinear,
      setter = setter,
      onComplete = onDone)

    check h.animator.activeCount == 1

    let p = newPilot(h)
    let wallStart = getMonoTime()
    p.waitForAnimation()
    let wallElapsed = (getMonoTime() - wallStart).inMilliseconds.int

    # No animations remain.
    check h.animator.activeCount == 0
    check completed == 1
    check abs(finalValue - 100.0) <= Tolerance

    # Virtual time advanced ~5000 ms.
    check h.clock.currentTime >= 5_000.0

    # No real wall-clock sleep — should be well under 500 ms even
    # with generous CI headroom.
    check wallElapsed < 500

    h.dispose()

  test "test_wait_for_scheduled_animations_drains":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var aDone = 0
    var bDone = 0
    let setterA = proc (v: float64) {.closure.} = discard
    let setterB = proc (v: float64) {.closure.} = discard
    let onDoneA = proc () {.closure.} = inc aDone
    let onDoneB = proc () {.closure.} = inc bDone
    h.animator.animateFloat(
      targetId = 1, attribute = "a",
      startValue = 0.0, endValue = 1.0,
      durationMs = 200.0, easingFn = easeLinear,
      setter = setterA, onComplete = onDoneA)
    h.animator.animateFloat(
      targetId = 2, attribute = "b",
      startValue = 0.0, endValue = 1.0,
      durationMs = 800.0, easingFn = easeLinear,
      setter = setterB, onComplete = onDoneB)

    let p = newPilot(h)
    p.waitForScheduledAnimations()
    check aDone == 1
    check bDone == 1
    check h.animator.activeCount == 0
    h.dispose()

  test "test_wait_for_animation_with_no_active_animations_is_noop":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    let p = newPilot(h)
    let timeBefore = h.clock.currentTime
    p.waitForAnimation()
    check h.clock.currentTime == timeBefore
    h.dispose()
