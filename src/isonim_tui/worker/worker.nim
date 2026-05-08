## isonim_tui/worker/worker.nim
##
## Port of `textual/worker.py` (455 LOC).
##
## A `Worker` represents an asynchronous (cooperative) unit of work
## scheduled against the harness's virtual clock. The worker is a
## state-machine with five lifecycle states (`pending`, `running`,
## `completed`, `cancelled`, `errored`) — the same taxonomy Textual
## uses, except we map Textual's `success` onto `completed` to avoid
## stuttering "success vs ok" wording in the cell-grid runtime.
##
## ## Design rationale (Charter alignment)
##
## * **Cooperative cancellation.** `cancelled` is a plain `bool` set
##   when `worker.cancel()` is called. The worker's body polls
##   `worker.checkCancelled()` (or any of the public predicates) and
##   exits cleanly when the flag flips. The clock-driven step
##   continuations also short-circuit when they observe a cancel, so
##   in-flight `scheduleNext` chains drop on the floor.
## * **Virtual clock.** Workers run their `body` immediately when
##   started (no thread spawn), and defer follow-up steps via
##   `clock.schedule(...)`. Under a `TestClock` this means the test
##   advances time and the worker progresses deterministically. Under
##   a `RealClock` (production) the same machinery works because
##   `RealClock.schedule` invokes the callback inline (its
##   implementation runs the work-loop synchronously today; future
##   async integration drops in here without API changes — see
##   `isonim/core/clock.nim`).
## * **Bridge to `isonim/core/resource.nim`.** The worker's terminal
##   states map onto the existing `ResourceState` enum: `running` →
##   `rsPending`, `completed` → `rsReady`, `errored` → `rsErrored`,
##   `cancelled` → `rsErrored` with a sentinel error message. The
##   bridge proc `toDeferredResource` returns a `DeferredResource[T]`
##   that resolves/rejects when the worker terminates — UI code that
##   already consumes `Resource[T]` plugs in unchanged.
## * **Type-erased base.** The manager owns a heterogeneous set of
##   workers (different `T`s coexist), so we split the type into a
##   non-generic `WorkerBase` (state + lifecycle plumbing) and a
##   generic `Worker[T]` that extends it with `result: T` and a typed
##   `onResult` signal-equivalent.
##
## ## Body shape
##
## Without first-class coroutines the body API is split into two
## callables:
##
## ```
## proc(w: Worker[T]) {.closure.}      ## the immediate body
## ```
##
## Inside the body the user may:
##
## * call `w.complete(value)`      — terminate now with success;
## * call `w.fail(msg)`             — terminate now with error;
## * call `w.scheduleStep(ms, p)`  — defer continuation to t+ms;
## * call `w.checkCancelled()`     — return early on cancellation.
##
## Most real workers chain `scheduleStep` calls to model "sleep then
## fetch then publish" — exactly the pattern Textual's `await
## asyncio.sleep` supports.

import isonim/core/clock

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  WorkerState* = enum
    ## Lifecycle states. Mirrors Textual's `WorkerState` 1:1 with
    ## `completed` standing in for `success` (more idiomatic in a
    ## cell-grid runtime that talks about "completed work").
    wsPending
    wsRunning
    wsCompleted
    wsCancelled
    wsErrored

  WorkerStateChangeProc* = proc (state: WorkerState) {.closure.}
    ## Signal-equivalent fired on every state transition. Delivered
    ## synchronously by the worker; subscribers may perform reactive
    ## writes (e.g. resolve a `DeferredResource`).

  WorkerBase* = ref object of RootRef
    ## Non-generic surface shared by every typed worker. The manager
    ## owns workers via `WorkerBase` so the per-screen set is
    ## heterogeneous over the result type `T`.
    name*: string
    group*: string
    description*: string
    state*: WorkerState
    cancelled*: bool             ## Cooperative-cancellation flag.
    error*: string               ## Set on `wsErrored`; empty otherwise.
    completedSteps*: int
    totalSteps*: int             ## 0 = indeterminate.
    nodeId*: int                 ## Widget/screen id that spawned this worker.
    createdTime*: float64        ## Wall (or virtual) creation timestamp.
    onStateChange*: WorkerStateChangeProc
    clock*: ClockBase
    pendingStepToken*: int       ## Outstanding clock-schedule token; -1 = none.
    pendingStepCb*: proc() {.closure.}
      ## Held so we can no-op it on cancel without relying on
      ## clock.cancel (cancel only works on TestClock; we want
      ## uniform behaviour).

  Worker*[T] = ref object of WorkerBase
    ## Typed worker. Owns the body closure and a typed `result`.
    body*: proc (w: Worker[T]) {.closure.}
    res*: T                       ## Result on `wsCompleted`. Field name
                                  ## avoids shadowing the built-in
                                  ## `result` injected into procs.
    onResult*: proc (value: T) {.closure.}
      ## Signal-equivalent fired exactly once when the worker
      ## terminates with `wsCompleted`. Subscribers see the typed
      ## value; on cancel/error this never fires.

# ----------------------------------------------------------------------------
# Time helpers (uniform interface over Real/Test clocks; matches animator).
# ----------------------------------------------------------------------------

proc currentTime(c: ClockBase): float64 =
  if c == nil:
    return 0.0
  if c of TestClock:
    return TestClock(c).now()
  if c of RealClock:
    return RealClock(c).now()
  0.0

proc scheduleCallback(c: ClockBase; cb: proc(); delayMs: float64): int =
  if c == nil:
    cb()
    return 0
  if c of TestClock:
    return TestClock(c).schedule(cb, delayMs)
  if c of RealClock:
    return RealClock(c).schedule(cb, delayMs)
  cb()
  return 0

# ----------------------------------------------------------------------------
# State helpers
# ----------------------------------------------------------------------------

proc setState*(w: WorkerBase; s: WorkerState) =
  ## Internal: transition the worker to `s` and fire the state-change
  ## signal. No-op when the state is unchanged so subscribers don't
  ## see duplicate notifications.
  if w.state == s: return
  w.state = s
  if w.onStateChange != nil:
    w.onStateChange(s)

proc isFinished*(w: WorkerBase): bool {.inline.} =
  ## True once the worker has reached a terminal state.
  w.state == wsCompleted or w.state == wsCancelled or w.state == wsErrored

proc isRunning*(w: WorkerBase): bool {.inline.} =
  w.state == wsRunning

proc isCancelled*(w: WorkerBase): bool {.inline.} =
  w.cancelled

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newWorker*[T](
    body: proc (w: Worker[T]) {.closure.};
    clock: ClockBase = nil;
    name: string = "";
    group: string = "default";
    description: string = "";
    nodeId: int = 0;
    onStateChange: WorkerStateChangeProc = nil;
    onResult: proc (value: T) {.closure.} = nil
): Worker[T] =
  ## Construct a fresh worker in the `wsPending` state. The body is
  ## not invoked until the manager (or the caller) starts the worker.
  result = Worker[T](
    name: name,
    group: group,
    description: description,
    state: wsPending,
    cancelled: false,
    error: "",
    completedSteps: 0,
    totalSteps: 0,
    nodeId: nodeId,
    createdTime: currentTime(clock),
    onStateChange: onStateChange,
    clock: clock,
    pendingStepToken: -1,
    pendingStepCb: nil,
    body: body,
    res: default(T),
    onResult: onResult)
  if result.onStateChange != nil:
    result.onStateChange(wsPending)

# ----------------------------------------------------------------------------
# Public mutation surface (called from inside the body, or from the manager)
# ----------------------------------------------------------------------------

proc complete*[T](w: Worker[T]; value: T) =
  ## Terminate the worker with `wsCompleted` and the given result.
  ## No-op if the worker is already finished. Fires `onResult` exactly
  ## once.
  if w.isFinished: return
  w.res = value
  w.error = ""
  w.pendingStepCb = nil
  w.pendingStepToken = -1
  w.setState(wsCompleted)
  if w.onResult != nil:
    w.onResult(value)

proc fail*(w: WorkerBase; msg: string) =
  ## Terminate the worker with `wsErrored`. The error message is
  ## stored on `w.error`. Subscribers to `onStateChange` see the
  ## transition; typed `onResult` does *not* fire on failure (matches
  ## Textual's semantics: `worker.result` is `None` on error).
  if w.isFinished: return
  w.error = msg
  w.pendingStepCb = nil
  w.pendingStepToken = -1
  w.setState(wsErrored)

proc cancel*(w: WorkerBase) =
  ## Mark the worker for cancellation. If the worker has already
  ## finished, this is a no-op. If the worker is in `wsPending` (not
  ## yet started) it transitions straight to `wsCancelled` — the body
  ## is never invoked. If the worker is `wsRunning` we set the flag
  ## and any subsequent `scheduleStep` callback bails out; the
  ## terminal `wsCancelled` transition fires from the body's exit (or
  ## from the next clock callback that observes the flag).
  if w.isFinished: return
  w.cancelled = true
  # Drop any in-flight continuation so it can't re-arm itself.
  w.pendingStepCb = nil
  w.pendingStepToken = -1
  if w.state == wsPending:
    w.setState(wsCancelled)
  else:
    # Running workers transition lazily; observers polling
    # `checkCancelled` move them to wsCancelled. Drive the transition
    # directly so callers that don't poll still see the terminal
    # state — matches Textual's `Worker.cancel` which marks
    # `cancelled_event` *and* immediately cancels the asyncio task.
    w.setState(wsCancelled)

proc checkCancelled*[T](w: Worker[T]): bool {.discardable.} =
  ## Cooperative poll. If the worker has been cancelled, transition
  ## to `wsCancelled` (idempotent — already done by `cancel`) and
  ## return true. The body is expected to call this between work
  ## chunks and exit early on `true`.
  if w.cancelled:
    if not w.isFinished:
      w.setState(wsCancelled)
    return true
  return false

proc advance*(w: WorkerBase; steps: int = 1) {.inline.} =
  ## Bump the completed-step counter (mirrors Textual's
  ## `Worker.advance`). Useful for progress UIs.
  w.completedSteps += steps

proc updateTotal*(w: WorkerBase; total: int) {.inline.} =
  ## Set the total expected steps. `0` means indeterminate.
  w.totalSteps = max(0, total)

proc progress*(w: WorkerBase): float =
  ## Progress as a percentage in `[0, 100]`. Indeterminate workers
  ## report `0.0`.
  if w.totalSteps <= 0: return 0.0
  let p = (w.completedSteps.float / w.totalSteps.float) * 100.0
  if p < 0.0: 0.0 elif p > 100.0: 100.0 else: p

# ----------------------------------------------------------------------------
# Step scheduling — the cooperative-async primitive
# ----------------------------------------------------------------------------

proc scheduleStep*[T](w: Worker[T]; delayMs: float64;
                      next: proc (w: Worker[T]) {.closure.}) =
  ## Defer continuation execution to `now + delayMs`. The continuation
  ## fires on the worker's clock; on a `TestClock` it fires when the
  ## test calls `harness.advance(...)` past the deadline.
  ##
  ## If the worker has already been cancelled we drop the
  ## continuation on the floor — the cancel-state was already
  ## published, no further callbacks should run.
  if w.isFinished or w.cancelled:
    return
  let captured = w
  let cb = proc() =
    # Re-check cancel/finish at fire time: state may have flipped
    # while the callback sat on the clock's queue.
    if captured.cancelled or captured.isFinished:
      return
    if captured.pendingStepCb == nil:
      # Cancel arrived between schedule and fire; bail.
      return
    captured.pendingStepCb = nil
    captured.pendingStepToken = -1
    if next != nil:
      next(captured)
  # Hold the closure so cancel can null it and break the chain.
  w.pendingStepCb = cb
  w.pendingStepToken = scheduleCallback(w.clock, cb, delayMs)

proc start*[T](w: Worker[T]) =
  ## Start a `wsPending` worker. Transitions to `wsRunning` and
  ## invokes the body immediately. Subsequent scheduling happens via
  ## `scheduleStep`. Idempotent — re-starting a running or finished
  ## worker is a no-op (matches Textual's `_start`).
  if w.state != wsPending: return
  if w.cancelled:
    # Pre-start cancellation — already moved to wsCancelled by
    # `cancel`. Nothing to do.
    return
  w.setState(wsRunning)
  if w.body != nil:
    try:
      w.body(w)
    except CatchableError as e:
      w.fail(e.msg)

# ----------------------------------------------------------------------------
# Bridge to isonim/core/resource.nim
# ----------------------------------------------------------------------------

import isonim/core/resource
import isonim/core/signals

proc bindToDeferredResource*[T](w: Worker[T]; dr: DeferredResource[T]) =
  ## Wire the worker's terminal transitions into a `DeferredResource`.
  ## On `wsCompleted` the resource resolves with the worker's result;
  ## on `wsErrored` it rejects with the worker's error message; on
  ## `wsCancelled` it rejects with the sentinel `"cancelled"`. This is
  ## the canonical hand-off for UI code that already speaks
  ## `Resource[T]`.
  let prev = w.onStateChange
  w.onStateChange = proc (s: WorkerState) {.closure.} =
    if prev != nil: prev(s)
    case s
    of wsCompleted:
      dr.resolve(w.res)
    of wsErrored:
      dr.reject(w.error)
    of wsCancelled:
      dr.reject("cancelled")
    else: discard

proc toDeferredResource*[T](w: Worker[T];
                            initialValue: T = default(T)): DeferredResource[T] =
  ## Convenience: build a fresh `DeferredResource[T]` and bind the
  ## worker's terminal transitions onto it.
  result = createDeferredResource[T](initialValue)
  w.bindToDeferredResource(result)

# Re-export the resource state enum so consumers don't need a second
# import to read the bridged state.
export resource.ResourceState, resource.Resource, resource.DeferredResource
export signals.Signal, signals.val
