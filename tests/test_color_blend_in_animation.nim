## test_color_blend_in_animation
##
## M7: animating a colour through the animator + Animatable blend
## protocol produces correct intermediate values.
##
## Animating background from rgb(255,0,0) to rgb(0,255,0) at the
## midpoint (factor=0.5 with the linear easing) produces (127,127,0).
## This is the byte-identical behaviour of M6's `blend` (linear-byte
## lerp). The "gamma-corrected" path lives behind `darken`/`lighten`
## (round-trips through Lab) — both surfaces are exposed through
## `animateBlendable`.

import unittest
import isonim_tui
import isonim_tui/theme/color as themeColor

suite "M7: color blend in animation":
  test "test_color_blend_in_animation_midpoint":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var captured: seq[themeColor.Color] = @[]
    let red = parseColor("rgb(255,0,0)")
    let green = parseColor("rgb(0,255,0)")
    let setter = proc (c: themeColor.Color) {.closure.} = captured.add c
    let blender = proc (s, e: themeColor.Color; f: float64): themeColor.Color {.closure.} =
      s.blend(e, f)

    h.animator.animateBlendable[:themeColor.Color](
      targetId = 1,
      attribute = "background",
      startValue = red,
      endValue = green,
      durationMs = 1_000.0,
      blender = blender,
      setter = setter,
      easingFn = easeLinear)

    # Drive in 50 ms steps so we get plenty of frames.
    while h.animator.activeCount > 0:
      h.advanceMs(50.0)

    check captured.len > 0

    # Find the frame closest to t=500ms (the linear midpoint).
    # Each frame fires at multiples of frameMs (~16.67ms); the captured
    # sequence is roughly evenly spaced.
    # Verify the *last* frame is at the destination.
    check captured[^1].r == 0u8
    check captured[^1].g == 255u8
    check captured[^1].b == 0u8

    # Find a frame near 50% factor: the captured value should be
    # approximately (127, 127, 0) — the byte-identical lerp.
    var midFound = false
    for c in captured:
      let dr = abs(c.r.int - 127)
      let dg = abs(c.g.int - 127)
      let db = c.b.int
      if dr <= 10 and dg <= 10 and db == 0:
        midFound = true
        break
    check midFound

    h.dispose()

  test "test_color_blend_animation_endpoints":
    # First captured frame should be a small step toward the
    # destination (not stuck at start, not at finish).
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    var firstFrame: themeColor.Color
    var captured = false
    let red = parseColor("rgb(255,0,0)")
    let blue = parseColor("rgb(0,0,255)")
    let setter = proc (c: themeColor.Color) {.closure.} =
      if not captured:
        firstFrame = c
        captured = true
    let blender = proc (s, e: themeColor.Color; f: float64): themeColor.Color {.closure.} =
      s.blend(e, f)
    h.animator.animateBlendable[:themeColor.Color](
      targetId = 1, attribute = "background",
      startValue = red, endValue = blue,
      durationMs = 1_000.0,
      blender = blender,
      setter = setter,
      easingFn = easeLinear)

    h.advanceMs(16.7)  # one frame
    check captured
    # First frame at ~1.67% should be very close to red.
    check firstFrame.r > 240
    check firstFrame.b < 20
    h.dispose()
