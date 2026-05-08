## isonim_tui/animation/animator.nim
##
## Port of `textual/_animator.py` (590 LOC).
##
## The animator is a frame-driven state machine that ticks at a fixed
## frame rate (60 Hz by default). On each tick it walks every active
## animation, computes the eased factor against the current time, and
## writes the interpolated value back through a per-animation
## `setter` callback. When the elapsed factor reaches 1.0 the animation
## is removed from the active set and (if still present) its
## `onComplete` callback fires.
##
## Charter notes
## -------------
## * Animations are stored as small value objects in a `seq[Animation]`
##   keyed by `(targetId, attribute)`. The animator itself is a `ref
##   object` because it owns mutable state shared across the harness
##   (active set, ticker handle, completion callbacks). That mirrors
##   M2's harness/compositor decision.
## * Time flows through `isonim/core/clock`. Tests construct a
##   `TestClock`; production wires a `RealClock`. The animator never
##   reads wall-clock time directly — it sees only what the clock
##   reports.
## * Generic value type: the per-animation closure stores its own
##   start/end values and `setter`. The animator core is type-erased
##   over `proc(progress: float64, eased: float64)`. This keeps the
##   active set heterogeneous (offset, alpha, color all live together)
##   without the runtime type-tagging Textual relies on.
## * Cancellation = remove from the active set and *do not* call
##   `onComplete`. Matches Textual's `force_stop_animation`.

import std/[tables]

import isonim/core/clock
import ./easing

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  AnimationKey* = tuple[targetId: int; attribute: string]
    ## Identity for an active animation. Mirrors Textual's
    ## `(id(obj), attribute)`. We use `int` instead of `id(obj)` since
    ## the renderer assigns deterministic per-thread node ids.

  AnimationStepProc* = proc (animationTime: float64;
                             eased: float64;
                             complete: bool) {.closure.}
    ## Per-frame callback. The animator calls this for every tick of
    ## an active animation, passing the wall time, the eased factor in
    ## [0, 1], and a flag set on the final tick. The closure owns the
    ## start/end values, the target object, and the setter — that's
    ## what makes the animator type-erased.

  AnimationCompleteProc* = proc () {.closure.}
    ## Optional callback fired after an animation reaches its end (and
    ## was not cancelled).

  Animation* = object
    ## A single active or scheduled animation. Stored by the animator
    ## as a value type (no individual `ref`).
    key*: AnimationKey
    startTime*: float64       ## Wall time at which the animation began.
    duration*: float64        ## Duration in *milliseconds*.
    easing*: EasingFunction
    step*: AnimationStepProc
    onComplete*: AnimationCompleteProc
    cancelled*: bool

  Animator* = ref object
    ## Top-level animator. One instance per app/harness. Manages a
    ## stream of active animations and a ticker scheduled through the
    ## clock so each frame fires deterministically under a TestClock.
    clock*: ClockBase
    framesPerSecond*: int
    frameMs*: float64               ## Cached `1000 / framesPerSecond`.
    active*: Table[AnimationKey, Animation]
    schedToken*: int                ## Outstanding clock-schedule token; -1 = none.
    started*: bool
    nextSeq*: int                   ## Monotonic per-key registration order.

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newAnimator*(clock: ClockBase; framesPerSecond: int = 60): Animator =
  Animator(
    clock: clock,
    framesPerSecond: framesPerSecond,
    frameMs: 1000.0 / framesPerSecond.float64,
    active: initTable[AnimationKey, Animation](),
    schedToken: -1,
    started: true,
    nextSeq: 0)

# ----------------------------------------------------------------------------
# Time helpers (uniform interface over Real/Test clocks)
# ----------------------------------------------------------------------------

proc currentTime*(a: Animator): float64 =
  if a.clock of TestClock:
    return TestClock(a.clock).now()
  if a.clock of RealClock:
    return RealClock(a.clock).now()
  0.0

proc scheduleCallback(a: Animator; cb: proc(); delayMs: float64): int =
  if a.clock of TestClock:
    return TestClock(a.clock).schedule(cb, delayMs)
  if a.clock of RealClock:
    return RealClock(a.clock).schedule(cb, delayMs)
  return 0

# ----------------------------------------------------------------------------
# Animation creation / cancellation
# ----------------------------------------------------------------------------

proc activeCount*(a: Animator): int {.inline.} =
  a.active.len

proc isAnimating*(a: Animator; targetId: int; attribute: string): bool {.inline.} =
  (targetId, attribute) in a.active

proc cancel*(a: Animator; targetId: int; attribute: string) =
  ## Remove the (targetId, attribute) animation. The current value
  ## becomes the frozen value (no further mutation), and `onComplete`
  ## is *not* fired. Matches Textual's `force_stop_animation` behaviour
  ## in the no-callback variant.
  let key: AnimationKey = (targetId, attribute)
  if key in a.active:
    a.active.del key

proc cancelAll*(a: Animator) =
  ## Drop every active animation. Test-suite helper; production
  ## callers usually cancel a single key.
  a.active.clear()

# ----------------------------------------------------------------------------
# Frame stepping
# ----------------------------------------------------------------------------

proc tick*(a: Animator)

proc scheduleNextFrame(a: Animator) =
  ## Re-arm the ticker for the next frame. If no animations are active
  ## we leave the schedule empty — we don't want to keep waking the
  ## clock for nothing.
  if a.active.len == 0:
    a.schedToken = -1
    return
  let token = a.scheduleCallback(proc() = a.tick(), a.frameMs)
  a.schedToken = token

proc tick*(a: Animator) =
  ## One frame of animation. Walks every active animation, advances
  ## its eased factor to the current clock time, and prunes finished
  ## ones. After the walk, if anything is still active, re-arm the
  ## next frame.
  if a.active.len == 0:
    a.schedToken = -1
    return

  let now = a.currentTime
  var doneKeys: seq[AnimationKey] = @[]
  var pendingCallbacks: seq[AnimationCompleteProc] = @[]

  # Snapshot keys before iterating: callbacks (and step procs) may
  # mutate the active set.
  var keys: seq[AnimationKey] = @[]
  for k in a.active.keys: keys.add k

  for k in keys:
    if k notin a.active: continue
    let anim = a.active[k]
    if anim.cancelled:
      doneKeys.add k
      continue

    var factor =
      if anim.duration <= 0.0: 1.0
      else: (now - anim.startTime) / anim.duration
    if factor < 0.0: factor = 0.0
    let complete = factor >= 1.0
    if factor > 1.0: factor = 1.0

    let eased = anim.easing(factor)
    if anim.step != nil:
      anim.step(now, eased, complete)

    if complete:
      doneKeys.add k
      if anim.onComplete != nil:
        pendingCallbacks.add anim.onComplete

  for k in doneKeys:
    a.active.del k

  for cb in pendingCallbacks:
    if cb != nil:
      cb()

  scheduleNextFrame(a)

proc registerAnimation*(a: Animator; anim: Animation) =
  ## Insert (or replace) an animation. If a previous animation existed
  ## for the same key, it is *replaced* — Textual's animator behaves
  ## the same way: animating the same attribute twice cancels the
  ## first run silently (the first run's `onComplete` does NOT fire,
  ## consistent with the cancel semantics).
  inc a.nextSeq
  a.active[anim.key] = anim
  if a.schedToken == -1:
    scheduleNextFrame(a)

# ----------------------------------------------------------------------------
# Generic float animator (the cell-grid case in Textual is a float).
# ----------------------------------------------------------------------------

proc animateFloat*(
    a: Animator;
    targetId: int;
    attribute: string;
    startValue, endValue: float64;
    durationMs: float64;
    easingFn: EasingFunction = easeInOutCubic;
    setter: proc (v: float64) {.closure.};
    onComplete: AnimationCompleteProc = nil;
    delayMs: float64 = 0.0
) =
  ## Convenience: animate a float attribute. `setter` receives the
  ## intermediate values; it's the caller's responsibility to push the
  ## value into the reactive graph (see `animateSignal` below).
  let easingFunc = if easingFn == nil: easeInOutCubic else: easingFn
  let key: AnimationKey = (targetId, attribute)
  let startTime = a.currentTime + delayMs

  # Capture the inputs in the step closure.
  let stepClosure: AnimationStepProc =
    proc (animationTime: float64; eased: float64; complete: bool) {.closure.} =
      let value =
        if complete: endValue
        else: startValue + (endValue - startValue) * eased
      if setter != nil:
        setter(value)

  let anim = Animation(
    key: key,
    startTime: startTime,
    duration: durationMs,
    easing: easingFunc,
    step: stepClosure,
    onComplete: onComplete,
    cancelled: false)

  if delayMs > 0.0:
    # Defer registration via the clock; matches Textual's `delay`
    # semantics (animation begins later, on_complete still fires when
    # it eventually completes).
    let captured = anim
    discard a.scheduleCallback(
      proc() = a.registerAnimation(captured), delayMs)
  else:
    a.registerAnimation(anim)

# ----------------------------------------------------------------------------
# Generic blend-protocol animator
# ----------------------------------------------------------------------------

proc animateBlendable*[T](
    a: Animator;
    targetId: int;
    attribute: string;
    startValue, endValue: T;
    durationMs: float64;
    blender: proc (s, e: T; factor: float64): T {.closure.};
    setter: proc (v: T) {.closure.};
    easingFn: EasingFunction = easeInOutCubic;
    onComplete: AnimationCompleteProc = nil;
    delayMs: float64 = 0.0
) =
  ## Animate any value type that has a blend protocol — the caller
  ## provides the `blender(start, end, factor) -> T`. This is how we
  ## animate Color, Scalar, and any user-defined Animatable.
  let easingFunc = if easingFn == nil: easeInOutCubic else: easingFn
  let key: AnimationKey = (targetId, attribute)
  let startTime = a.currentTime + delayMs

  let stepClosure: AnimationStepProc =
    proc (animationTime: float64; eased: float64; complete: bool) {.closure.} =
      let value =
        if complete: endValue
        else: blender(startValue, endValue, eased)
      if setter != nil:
        setter(value)

  let anim = Animation(
    key: key,
    startTime: startTime,
    duration: durationMs,
    easing: easingFunc,
    step: stepClosure,
    onComplete: onComplete,
    cancelled: false)

  if delayMs > 0.0:
    let captured = anim
    discard a.scheduleCallback(
      proc() = a.registerAnimation(captured), delayMs)
  else:
    a.registerAnimation(anim)

# ----------------------------------------------------------------------------
# Idle / completion helpers
# ----------------------------------------------------------------------------

proc waitForIdle*(a: Animator; advanceClock: bool = true;
                  maxFrames: int = 1_000_000): int =
  ## Drive the clock forward in `frameMs` increments until the animator
  ## has no active animations. Returns the number of frames advanced.
  ## Used by Pilot.waitForAnimation under a TestClock — under a
  ## RealClock callers usually run their event loop directly. If the
  ## clock isn't a TestClock and `advanceClock` is true we still loop
  ## through `tick()` calls so on-completion callbacks fire, but we
  ## won't advance time (the RealClock's `now()` ticks naturally).
  result = 0
  if a.clock of TestClock:
    let tc = TestClock(a.clock)
    while a.active.len > 0 and result < maxFrames:
      if advanceClock:
        tc.advance(a.frameMs)
      else:
        a.tick()
      inc result
  else:
    while a.active.len > 0 and result < maxFrames:
      a.tick()
      inc result

# ----------------------------------------------------------------------------
# Active introspection (used by the Pilot for `waitForScheduledAnimations`)
# ----------------------------------------------------------------------------

proc activeKeys*(a: Animator): seq[AnimationKey] =
  result = @[]
  for k in a.active.keys: result.add k
