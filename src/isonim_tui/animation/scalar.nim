## isonim_tui/animation/scalar.nim
##
## Port of `textual/css/scalar_animation.py` (~100 LOC).
##
## Animates CSS scalars (sizes, offsets, alpha) — values that resolve
## to a number under a viewport but that we want the *eased* result to
## be in scalar-units, not raw pixels. We blend in resolved-cell space
## then write the blended cells back into the live styles.
##
## Animating colors lives in `animator.animateBlendable[Color]` (see
## the cross-cutting `Animatable` section); this module focuses on
## numeric CSS scalars where blending is just a linear interpolation
## in cell space, possibly combined with the M5 unit resolver.

import ../css/properties
import ./animator
import ./easing

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc resolveScalar*(s: Scalar; refSize, viewport: float64): float64 =
  ## Convert a `Scalar` to a concrete cell value within a reference
  ## size + viewport. Mirrors `css.scalar.Scalar.resolve` for the units
  ## the M5 engine ships today.
  case s.unit
  of suCells: s.value
  of suPercent: s.value / 100.0 * refSize
  of suFr: s.value
    # `fr` only resolves inside a grid track sizer; outside of a grid
    # we fall through to its raw weight. (Animating `fr` is not in
    # the M7 surface but we keep it numerically defined.)
  of suViewW: s.value / 100.0 * viewport
  of suViewH: s.value / 100.0 * viewport
  of suAuto: 0.0

proc blendScalar*(s, e: Scalar; factor: float64): Scalar =
  ## Linear blend between two scalars. If both are the same unit, blend
  ## within that unit. Otherwise resolve into cell space (caller is
  ## responsible for picking the reference size — the cell-blend below
  ## is a fallback that assumes both are already in cells).
  if s.unit == e.unit:
    return Scalar(unit: s.unit, value: s.value + (e.value - s.value) * factor)
  return Scalar(unit: suCells, value: s.value + (e.value - s.value) * factor)

# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

proc animateScalar*(
    a: Animator;
    targetId: int;
    attribute: string;
    startValue, endValue: Scalar;
    durationMs: float64;
    setter: proc (v: Scalar) {.closure.};
    easingFn: EasingFunction = easeInOutCubic;
    onComplete: AnimationCompleteProc = nil;
    delayMs: float64 = 0.0
) =
  ## Animate a `Scalar` attribute. Uses `blendScalar` as the blend
  ## protocol; the animator handles the easing curve, the timing, and
  ## the cancellation semantics.
  animateBlendable[Scalar](
    a, targetId, attribute,
    startValue, endValue, durationMs,
    proc (s, e: Scalar; factor: float64): Scalar {.closure.} =
      blendScalar(s, e, factor),
    setter,
    easingFn, onComplete, delayMs)

proc animateAlpha*(
    a: Animator;
    targetId: int;
    attribute: string;
    startAlpha, endAlpha: float64;
    durationMs: float64;
    setter: proc (v: float64) {.closure.};
    easingFn: EasingFunction = easeInOutCubic;
    onComplete: AnimationCompleteProc = nil;
    delayMs: float64 = 0.0
) =
  ## Convenience: animate an alpha (or any pure float in [0, 1]).
  ## Same shape as `animateScalar` but with a flat float value.
  animateFloat(a, targetId, attribute,
               startAlpha, endAlpha, durationMs,
               easingFn, setter, onComplete, delayMs)
