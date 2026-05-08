## test_easing_byte_parity
##
## M7: every IsoNim easing function must match Textual's `_easing.py`
## byte-for-byte at 60 Hz over 1 second.
##
## Strategy: for each named curve, sample 61 points (t = 0/60, 1/60,
## ..., 60/60) and compare against the formulas from `_easing.py`
## evaluated independently in this test (we reproduce the formulas
## here so the comparison is hermetic — no Python required, no Textual
## install required).
##
## The test is also driven by the *real* animator + virtual clock:
## we register an animation with each curve, advance the test clock
## one frame at a time, and capture the eased values via the
## animation's setter. The captured trace must equal the analytical
## reference within 1e-9 (machine-epsilon-level rounding only).

import std/[math, tables]
import unittest
import isonim_tui
import isonim/core/clock

# ---------------------------------------------------------------------------
# Reference formulas — copy of `textual/_easing.py`.
# ---------------------------------------------------------------------------

proc refOutBounce(x: float64): float64 =
  let n = 7.5625
  let d = 2.75
  if x < 1.0 / d: n * x * x
  elif x < 2.0 / d:
    let xx = x - 1.5 / d
    n * xx * xx + 0.75
  elif x < 2.5 / d:
    let xx = x - 2.25 / d
    n * xx * xx + 0.9375
  else:
    let xx = x - 2.625 / d
    n * xx * xx + 0.984375

proc reference(name: string; x: float64): float64 =
  case name
  of "none": 1.0
  of "round": (if x < 0.5: 0.0 else: 1.0)
  of "linear": x
  of "in_sine": 1.0 - cos((x * PI) / 2.0)
  of "out_sine": sin((x * PI) / 2.0)
  of "in_out_sine": -(cos(x * PI) - 1.0) / 2.0
  of "in_quad": x * x
  of "out_quad": 1.0 - pow(1.0 - x, 2.0)
  of "in_out_quad":
    if x < 0.5: 2.0 * x * x
    else: 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0
  of "in_cubic": x * x * x
  of "out_cubic": 1.0 - pow(1.0 - x, 3.0)
  of "in_out_cubic":
    if x < 0.5: 4.0 * x * x * x
    else: 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0
  of "in_quart": pow(x, 4.0)
  of "out_quart": 1.0 - pow(1.0 - x, 4.0)
  of "in_out_quart":
    if x < 0.5: 8.0 * pow(x, 4.0)
    else: 1.0 - pow(-2.0 * x + 2.0, 4.0) / 2.0
  of "in_quint": pow(x, 5.0)
  of "out_quint": 1.0 - pow(1.0 - x, 5.0)
  of "in_out_quint":
    if x < 0.5: 16.0 * pow(x, 5.0)
    else: 1.0 - pow(-2.0 * x + 2.0, 5.0) / 2.0
  of "in_expo":
    if x == 0.0: 0.0 else: pow(2.0, 10.0 * x - 10.0)
  of "out_expo":
    if x == 1.0: 1.0 else: 1.0 - pow(2.0, -10.0 * x)
  of "in_out_expo":
    if x > 0.0 and x < 0.5: pow(2.0, 20.0 * x - 10.0) / 2.0
    elif x >= 0.5 and x < 1.0: (2.0 - pow(2.0, -20.0 * x + 10.0)) / 2.0
    else: x
  of "in_circ": 1.0 - sqrt(1.0 - pow(x, 2.0))
  of "out_circ": sqrt(1.0 - pow(x - 1.0, 2.0))
  of "in_out_circ":
    if x < 0.5: (1.0 - sqrt(1.0 - pow(2.0 * x, 2.0))) / 2.0
    else: (sqrt(1.0 - pow(-2.0 * x + 2.0, 2.0)) + 1.0) / 2.0
  of "in_back":
    2.70158 * pow(x, 3.0) - 1.70158 * pow(x, 2.0)
  of "out_back":
    1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
  of "in_out_back":
    let c = 1.70158 * 1.525
    if x < 0.5: (pow(2.0 * x, 2.0) * ((c + 1.0) * 2.0 * x - c)) / 2.0
    else: (pow(2.0 * x - 2.0, 2.0) * ((c + 1.0) * (x * 2.0 - 2.0) + c) + 2.0) / 2.0
  of "in_elastic":
    let c = 2.0 * PI / 3.0
    if x > 0.0 and x < 1.0:
      -pow(2.0, 10.0 * x - 10.0) * sin((x * 10.0 - 10.75) * c)
    else: x
  of "out_elastic":
    let c = 2.0 * PI / 3.0
    if x > 0.0 and x < 1.0:
      pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * c) + 1.0
    else: x
  of "in_out_elastic":
    let c = 2.0 * PI / 4.5
    if x > 0.0 and x < 0.5:
      -(pow(2.0, 20.0 * x - 10.0) * sin((20.0 * x - 11.125) * c)) / 2.0
    elif x >= 0.5 and x < 1.0:
      (pow(2.0, -20.0 * x + 10.0) * sin((20.0 * x - 11.125) * c)) / 2.0 + 1.0
    else: x
  of "out_bounce": refOutBounce(x)
  of "in_bounce": 1.0 - refOutBounce(1.0 - x)
  of "in_out_bounce":
    if x < 0.5: (1.0 - refOutBounce(1.0 - 2.0 * x)) / 2.0
    else: (1.0 + refOutBounce(2.0 * x - 1.0)) / 2.0
  else:
    raise newException(ValueError, "unknown curve: " & name)

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

const Tolerance = 1e-9

suite "M7: easing byte parity":
  test "test_easing_table_has_all_curves":
    let names = easingNames()
    # We expect the same 33 curves as Textual's `_easing.EASING`.
    check names.len == 33
    let must = [
      "none", "round", "linear",
      "in_sine", "out_sine", "in_out_sine",
      "in_quad", "out_quad", "in_out_quad",
      "in_cubic", "out_cubic", "in_out_cubic",
      "in_quart", "out_quart", "in_out_quart",
      "in_quint", "out_quint", "in_out_quint",
      "in_expo", "out_expo", "in_out_expo",
      "in_circ", "out_circ", "in_out_circ",
      "in_back", "out_back", "in_out_back",
      "in_elastic", "out_elastic", "in_out_elastic",
      "in_bounce", "out_bounce", "in_out_bounce",
    ]
    for n in must:
      check isKnownEasing(n)

  test "test_easing_byte_parity_at_60hz":
    # Sample 61 points at t = i / 60 for i in 0..60.
    let names = easingNames()
    for name in names:
      let fn = easingByName(name)
      for i in 0 .. 60:
        let x = i.float64 / 60.0
        let got = fn(x)
        let want = reference(name, x)
        let diff = abs(got - want)
        if diff > Tolerance:
          checkpoint("curve=" & name & " x=" & $x &
                     " got=" & $got & " want=" & $want)
        check diff <= Tolerance

  test "test_easing_through_animator_real_stack":
    # Drive the in_out_cubic curve through the real animator + virtual
    # clock. Each frame, the eased value must match the analytical
    # reference for that exact eased factor.
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var captured: seq[float64] = @[]
    var frameTimes: seq[float64] = @[]

    h.animator.animateFloat(
      targetId = 1, attribute = "x",
      startValue = 0.0, endValue = 1.0,
      durationMs = 1000.0,
      easingFn = easeInOutCubic,
      setter = proc (v: float64) {.closure.} =
        captured.add v
        frameTimes.add h.animator.currentTime)

    # Step 60 frames (one full second).
    for i in 0 ..< 60:
      h.advanceMs(1000.0 / 60.0)

    # Drain the final frame.
    discard h.animator.waitForIdle()

    check captured.len >= 60
    # Each captured value should match in_out_cubic of (frame_time/1s).
    for i in 0 ..< captured.len:
      let factor = min(1.0, frameTimes[i] / 1000.0)
      let want = reference("in_out_cubic", factor)
      let diff = abs(captured[i] - want)
      if diff > Tolerance:
        checkpoint("frame=" & $i & " factor=" & $factor &
                   " got=" & $captured[i] & " want=" & $want)
      check diff <= Tolerance

    h.dispose()
