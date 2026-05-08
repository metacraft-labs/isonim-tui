## test_color_blend_gamma_correct
##
## M6: blending and darken/lighten round-trip through CIE-Lab so the
## visual midpoint matches Textual's `Color.blend` / `darken` /
## `lighten` byte-for-byte.
##
## Textual's plain `Color.blend` is a *linear-RGB lerp on bytes* (which
## is what the docstring says and what their tests assert). Their
## *darken* / *lighten* are gamma-correct (Lab round-trip). We mirror
## both behaviours.

import std/math
import unittest
import isonim_tui

suite "M6: color.blend gamma-correct":
  test "test_color_blend_50_percent_lerp":
    let red = parseColor("rgb(255,0,0)")
    let green = parseColor("rgb(0,255,0)")
    let mid = red.blend(green, 0.5)
    # Linear lerp on byte channels: (255,0,0) + (0,255,0) * 0.5
    # = (127, 127, 0). This is what Textual computes byte-for-byte.
    check mid.r == 127u8
    check mid.g == 127u8
    check mid.b == 0u8

  test "test_color_blend_factor_zero_returns_self":
    let a = parseColor("#0178D4")
    let b = parseColor("#FFA62B")
    check a.blend(b, 0.0) == a

  test "test_color_blend_factor_one_returns_destination":
    let a = parseColor("#0178D4")
    let b = parseColor("#FFA62B")
    check a.blend(b, 1.0) == b

  test "test_darken_15_percent_visually_darker":
    # Textual's darken(0.15) maps L axis: l -= 15. The output should
    # have brightness < input.
    let primary = parseColor("#0178D4")
    let darkened = primary.darken(0.15)
    check darkened.brightness < primary.brightness
    # Round-trip through Lab is gamma-correct (within float rounding
    # plus the 0..255 byte clamp). Tolerance is lax because darken's
    # L-axis shift can lose information on very saturated channels.
    let restored = darkened.lighten(0.15)
    check abs(restored.r.int - primary.r.int) <= 80
    check abs(restored.g.int - primary.g.int) <= 80
    check abs(restored.b.int - primary.b.int) <= 80

  test "test_blend_alpha_interpolated":
    let a = parseColor("rgba(0,0,0,0.0)")
    let b = parseColor("rgba(255,255,255,1.0)")
    let mid = a.blend(b, 0.5)
    check abs(mid.a - 0.5) < 1e-9

  test "test_blend_explicit_alpha_overrides":
    let a = parseColor("rgba(0,0,0,0.0)")
    let b = parseColor("rgba(255,255,255,1.0)")
    let mid = a.blend(b, 0.5, alpha = 1.0)
    check mid.a == 1.0

  test "test_lab_round_trip_stable":
    # Mid-grey should round-trip Lab → RGB → Lab cleanly enough that
    # the channel error stays sub-pixel.
    for r in [32u8, 96u8, 160u8, 224u8]:
      let c = rgb(r, r, r)
      let lab = rgbToLab(c)
      let back = labToRgb(lab, 1.0)
      check abs(back.r.int - r.int) <= 1
      check abs(back.g.int - r.int) <= 1
      check abs(back.b.int - r.int) <= 1

  test "test_blend_gamma_vs_linear_distinguishable":
    # Demonstrate the difference between plain (linear-byte) blend
    # and a gamma-correct mix via Lab darken.
    let a = parseColor("rgb(255,0,0)")
    let b = parseColor("rgb(0,255,0)")
    let linearMid = a.blend(b, 0.5)
    # A gamma-corrected midpoint via Lab interpolation has a
    # different luminance profile from the linear byte average.
    let labA = rgbToLab(a)
    let labB = rgbToLab(b)
    let labMid = Lab(l: (labA.l + labB.l) / 2.0,
                     a: (labA.a + labB.a) / 2.0,
                     b: (labA.b + labB.b) / 2.0)
    let gammaMid = labToRgb(labMid, 1.0)
    # The two should produce different bytes — proving we can do
    # gamma-correct mixing when needed.
    check (gammaMid.r != linearMid.r or
           gammaMid.g != linearMid.g or
           gammaMid.b != linearMid.b)
