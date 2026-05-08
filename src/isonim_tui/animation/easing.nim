## isonim_tui/animation/easing.nim
##
## Port of `textual/_easing.py` (~150 LOC, 33 functions).
##
## Each easing maps the unit interval [0, 1] -> [0, 1] (the "factor"
## domain). At factor 0 the animation is at its start value, at factor 1
## the animation is at its destination. Curves return values that may
## briefly leave the unit interval (e.g. `back`, `elastic`) — that is
## intentional and matches Textual byte-for-byte.
##
## Charter: easing functions are pure value-typed `proc` values. No
## ref objects. The `EasingFunction` type is a `proc(x: float64): float64`
## with no closure environment, so they survive the same `--mm:arc/orc/refc`
## matrix as the rest of the repo.
##
## We export both the named curve table (string -> `EasingFunction`) and
## individual functions so callers can pick whichever feels best.

import std/[math, tables]

type
  EasingFunction* = proc(x: float64): float64 {.nimcall, noSideEffect.}
    ## Map factor in [0, 1] to factor in [0, 1] (with possible
    ## overshoot for back / elastic). Pure function.

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

const
  DefaultEasing* = "in_out_cubic"
    ## Match `_easing.DEFAULT_EASING`.
  DefaultScrollEasing* = "out_cubic"
    ## Match `_easing.DEFAULT_SCROLL_EASING`.

# ----------------------------------------------------------------------------
# Curves — implementations match Textual's `_easing.py` byte-for-byte.
# ----------------------------------------------------------------------------

proc easeNone*(x: float64): float64 {.nimcall, noSideEffect.} =
  ## `lambda x: 1.0` — instantly at the destination, ignores progress.
  1.0

proc easeRound*(x: float64): float64 {.nimcall, noSideEffect.} =
  ## Snap at the midpoint: 0 below 0.5, 1 above.
  if x < 0.5: 0.0 else: 1.0

proc easeLinear*(x: float64): float64 {.nimcall, noSideEffect.} =
  x

# --- sine ---

proc easeInSine*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - cos((x * PI) / 2.0)

proc easeOutSine*(x: float64): float64 {.nimcall, noSideEffect.} =
  sin((x * PI) / 2.0)

proc easeInOutSine*(x: float64): float64 {.nimcall, noSideEffect.} =
  -(cos(x * PI) - 1.0) / 2.0

# --- quad ---

proc easeInQuad*(x: float64): float64 {.nimcall, noSideEffect.} =
  x * x

proc easeOutQuad*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - pow(1.0 - x, 2.0)

proc easeInOutQuad*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5: 2.0 * x * x
  else: 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0

# --- cubic ---

proc easeInCubic*(x: float64): float64 {.nimcall, noSideEffect.} =
  x * x * x

proc easeOutCubic*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - pow(1.0 - x, 3.0)

proc easeInOutCubic*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5: 4.0 * x * x * x
  else: 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

# --- quart ---

proc easeInQuart*(x: float64): float64 {.nimcall, noSideEffect.} =
  pow(x, 4.0)

proc easeOutQuart*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - pow(1.0 - x, 4.0)

proc easeInOutQuart*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5: 8.0 * pow(x, 4.0)
  else: 1.0 - pow(-2.0 * x + 2.0, 4.0) / 2.0

# --- quint ---

proc easeInQuint*(x: float64): float64 {.nimcall, noSideEffect.} =
  pow(x, 5.0)

proc easeOutQuint*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - pow(1.0 - x, 5.0)

proc easeInOutQuint*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5: 16.0 * pow(x, 5.0)
  else: 1.0 - pow(-2.0 * x + 2.0, 5.0) / 2.0

# --- expo ---

proc easeInExpo*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x == 0.0: 0.0 else: pow(2.0, 10.0 * x - 10.0)

proc easeOutExpo*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x == 1.0: 1.0 else: 1.0 - pow(2.0, -10.0 * x)

proc easeInOutExpo*(x: float64): float64 {.nimcall, noSideEffect.} =
  ## Textual's `_in_out_expo`: returns x at the boundaries (0 and 1).
  if x > 0.0 and x < 0.5:
    pow(2.0, 20.0 * x - 10.0) / 2.0
  elif x >= 0.5 and x < 1.0:
    (2.0 - pow(2.0, -20.0 * x + 10.0)) / 2.0
  else:
    x

# --- circ ---

proc easeInCirc*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - sqrt(1.0 - pow(x, 2.0))

proc easeOutCirc*(x: float64): float64 {.nimcall, noSideEffect.} =
  sqrt(1.0 - pow(x - 1.0, 2.0))

proc easeInOutCirc*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5:
    (1.0 - sqrt(1.0 - pow(2.0 * x, 2.0))) / 2.0
  else:
    (sqrt(1.0 - pow(-2.0 * x + 2.0, 2.0)) + 1.0) / 2.0

# --- back ---

proc easeInBack*(x: float64): float64 {.nimcall, noSideEffect.} =
  2.70158 * pow(x, 3.0) - 1.70158 * pow(x, 2.0)

proc easeOutBack*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)

proc easeInOutBack*(x: float64): float64 {.nimcall, noSideEffect.} =
  let c = 1.70158 * 1.525
  if x < 0.5:
    (pow(2.0 * x, 2.0) * ((c + 1.0) * 2.0 * x - c)) / 2.0
  else:
    (pow(2.0 * x - 2.0, 2.0) * ((c + 1.0) * (x * 2.0 - 2.0) + c) + 2.0) / 2.0

# --- elastic ---

proc easeInElastic*(x: float64): float64 {.nimcall, noSideEffect.} =
  let c = 2.0 * PI / 3.0
  if x > 0.0 and x < 1.0:
    -pow(2.0, 10.0 * x - 10.0) * sin((x * 10.0 - 10.75) * c)
  else:
    x

proc easeOutElastic*(x: float64): float64 {.nimcall, noSideEffect.} =
  let c = 2.0 * PI / 3.0
  if x > 0.0 and x < 1.0:
    pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * c) + 1.0
  else:
    x

proc easeInOutElastic*(x: float64): float64 {.nimcall, noSideEffect.} =
  let c = 2.0 * PI / 4.5
  if x > 0.0 and x < 0.5:
    -(pow(2.0, 20.0 * x - 10.0) * sin((20.0 * x - 11.125) * c)) / 2.0
  elif x >= 0.5 and x < 1.0:
    (pow(2.0, -20.0 * x + 10.0) * sin((20.0 * x - 11.125) * c)) / 2.0 + 1.0
  else:
    x

# --- bounce ---

proc easeOutBounce*(x: float64): float64 {.nimcall, noSideEffect.} =
  let n = 7.5625
  let d = 2.75
  if x < 1.0 / d:
    n * x * x
  elif x < 2.0 / d:
    let xx = x - 1.5 / d
    n * xx * xx + 0.75
  elif x < 2.5 / d:
    let xx = x - 2.25 / d
    n * xx * xx + 0.9375
  else:
    let xx = x - 2.625 / d
    n * xx * xx + 0.984375

proc easeInBounce*(x: float64): float64 {.nimcall, noSideEffect.} =
  1.0 - easeOutBounce(1.0 - x)

proc easeInOutBounce*(x: float64): float64 {.nimcall, noSideEffect.} =
  if x < 0.5:
    (1.0 - easeOutBounce(1.0 - 2.0 * x)) / 2.0
  else:
    (1.0 + easeOutBounce(2.0 * x - 1.0)) / 2.0

# ----------------------------------------------------------------------------
# Easing table — string -> EasingFunction. Same names as `_easing.EASING`.
# ----------------------------------------------------------------------------

proc buildEasingTable(): Table[string, EasingFunction] =
  result = initTable[string, EasingFunction]()
  result["none"] = easeNone
  result["round"] = easeRound
  result["linear"] = easeLinear
  result["in_sine"] = easeInSine
  result["out_sine"] = easeOutSine
  result["in_out_sine"] = easeInOutSine
  result["in_quad"] = easeInQuad
  result["out_quad"] = easeOutQuad
  result["in_out_quad"] = easeInOutQuad
  result["in_cubic"] = easeInCubic
  result["out_cubic"] = easeOutCubic
  result["in_out_cubic"] = easeInOutCubic
  result["in_quart"] = easeInQuart
  result["out_quart"] = easeOutQuart
  result["in_out_quart"] = easeInOutQuart
  result["in_quint"] = easeInQuint
  result["out_quint"] = easeOutQuint
  result["in_out_quint"] = easeInOutQuint
  result["in_expo"] = easeInExpo
  result["out_expo"] = easeOutExpo
  result["in_out_expo"] = easeInOutExpo
  result["in_circ"] = easeInCirc
  result["out_circ"] = easeOutCirc
  result["in_out_circ"] = easeInOutCirc
  result["in_back"] = easeInBack
  result["out_back"] = easeOutBack
  result["in_out_back"] = easeInOutBack
  result["in_elastic"] = easeInElastic
  result["out_elastic"] = easeOutElastic
  result["in_out_elastic"] = easeInOutElastic
  result["in_bounce"] = easeInBounce
  result["out_bounce"] = easeOutBounce
  result["in_out_bounce"] = easeInOutBounce

let Easing* = buildEasingTable()
  ## Map of easing name -> function. Same set Textual ships in
  ## `_easing.EASING`. 33 entries.

proc easingByName*(name: string): EasingFunction =
  ## Resolve a curve by name. Returns the linear curve for unknown
  ## names — same default behaviour as `EASING.get(name, EASING['linear'])`
  ## in Textual when the name is unknown (Textual would `KeyError`, but
  ## we prefer a graceful fall-through that callers can detect by
  ## comparing against `easeLinear`).
  if name in Easing: Easing[name]
  else: easeLinear

proc isKnownEasing*(name: string): bool {.inline.} =
  name in Easing

proc easingNames*(): seq[string] =
  ## All registered easing names. Useful for tests that iterate every
  ## curve — the parity tests sample each curve at 60 Hz and compare.
  result = @[]
  for k in Easing.keys:
    result.add k
