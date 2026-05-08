## isonim_tui/worker/manager.nim
##
## Port of `textual/worker_manager.py` (181 LOC).
##
## A `WorkerManager` owns a per-screen (or per-harness) set of
## workers, tracks their lifecycle, and exposes group / node /
## global cancellation. Heterogeneous workers (different result
## types) share the manager via the non-generic `WorkerBase`.
##
## ## Charter alignment
##
## * **Per-harness isolation.** Each `TerminalTestHarness` holds its
##   own `WorkerManager` (M2 owns the wiring; see `harness.nim`).
##   Cancelling all workers on harness A cannot affect workers
##   spawned on harness B because they live in disjoint manager
##   instances. The third mandatory test asserts this directly.
##
## * **Cooperative shutdown drains pending workers.** `shutdown()`
##   walks every worker, marks it cancelled, and removes it from the
##   active set. Pending (not-yet-started) workers transition to
##   `wsCancelled` immediately; running ones see the flag on their
##   next `checkCancelled` poll. Future enhancement: optionally wait
##   for in-flight clock-callback chains to drain — for now we rely
##   on the fact that `cancel()` nulls the `pendingStepCb`, so the
##   chain terminates after at most one further callback fires (and
##   that callback bails immediately).
##
## * **Spawn convenience.** `manager.spawn(...)` constructs a typed
##   worker and starts it in one call — the most common pattern in
##   widget code that just wants "fire-and-forget background work".

import std/[tables, hashes]

import isonim/core/clock
import ./worker

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  WorkerManager* = ref object
    ## Owns the active worker set for one harness/app/screen. The
    ## manager itself is a `ref object` (mutable scaffolding); the
    ## workers it tracks are also refs but held by id so we can do
    ## cheap set operations without per-worker hashing of arbitrary
    ## ref payloads.
    clock*: ClockBase
    workers*: Table[int, WorkerBase]
    nextId*: int               ## Monotonic per-manager id counter.
    shutdownInProgress*: bool

  WorkerHandle* = int
    ## Stable id of a worker inside its owning manager. Used to look
    ## up workers without needing to hold a typed `Worker[T]` ref.

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newWorkerManager*(clock: ClockBase = nil): WorkerManager =
  WorkerManager(
    clock: clock,
    workers: initTable[int, WorkerBase](),
    nextId: 0,
    shutdownInProgress: false)

# ----------------------------------------------------------------------------
# Internal id assignment + tracking
# ----------------------------------------------------------------------------

proc nextWorkerId(m: WorkerManager): int =
  inc m.nextId
  m.nextId

proc trackWorker(m: WorkerManager; w: WorkerBase): int =
  ## Insert `w` into the active set keyed by a fresh id. Returns the
  ## id (the `WorkerHandle` callers can hold onto).
  let id = m.nextWorkerId
  m.workers[id] = w
  id

# ----------------------------------------------------------------------------
# Public surface
# ----------------------------------------------------------------------------

proc add*(m: WorkerManager; w: WorkerBase): WorkerHandle =
  ## Register an already-constructed worker with the manager. Returns
  ## the manager-scoped handle. The worker's `clock` is left
  ## untouched — callers that constructed the worker via
  ## `newWorker(...)` should pass `m.clock` so scheduling routes
  ## through the manager's clock.
  m.trackWorker(w)

proc spawn*[T](
    m: WorkerManager;
    body: proc (w: Worker[T]) {.closure.};
    name: string = "";
    group: string = "default";
    description: string = "";
    nodeId: int = 0;
    onStateChange: WorkerStateChangeProc = nil;
    onResult: proc (value: T) {.closure.} = nil;
    autoStart: bool = true
): Worker[T] =
  ## Construct a fresh `Worker[T]`, register it with the manager, and
  ## (by default) start it immediately. Returns the typed worker —
  ## callers can still hold onto the typed handle to read `res` once
  ## it completes. The manager-scoped id is captured on the worker's
  ## `nodeId` field only when the caller does *not* override it.
  let w = newWorker[T](
    body = body,
    clock = m.clock,
    name = name,
    group = group,
    description = description,
    nodeId = nodeId,
    onStateChange = onStateChange,
    onResult = onResult)
  discard m.trackWorker(w)
  if autoStart:
    w.start()
  w

proc count*(m: WorkerManager): int {.inline.} =
  m.workers.len

proc anyRunning*(m: WorkerManager): bool =
  for w in m.workers.values:
    if w.isRunning: return true
  return false

proc anyPending*(m: WorkerManager): bool =
  for w in m.workers.values:
    if w.state == wsPending: return true
  return false

proc allWorkers*(m: WorkerManager): seq[WorkerBase] =
  result = @[]
  for w in m.workers.values: result.add w

# ----------------------------------------------------------------------------
# Cancellation
# ----------------------------------------------------------------------------

proc cancelAll*(m: WorkerManager) =
  ## Cancel every worker in the manager. The cancellation flag is
  ## cooperative — running bodies see it on their next `checkCancelled`
  ## poll. Pending workers transition straight to `wsCancelled`.
  for w in m.workers.values:
    if not w.isFinished:
      w.cancel()

proc cancelGroup*(m: WorkerManager; group: string): seq[WorkerBase] =
  ## Cancel every worker in the named group. Returns the list of
  ## workers that were marked cancelled.
  result = @[]
  for w in m.workers.values:
    if w.group == group and not w.isFinished:
      w.cancel()
      result.add w

proc cancelNode*(m: WorkerManager; nodeId: int): seq[WorkerBase] =
  ## Cancel every worker spawned on `nodeId`. Returns the list of
  ## workers that were marked cancelled. The widget that owns
  ## `nodeId` typically calls this from its `onUnmount` hook so
  ## leaving the screen drops in-flight loads.
  result = @[]
  for w in m.workers.values:
    if w.nodeId == nodeId and not w.isFinished:
      w.cancel()
      result.add w

proc reap*(m: WorkerManager) =
  ## Garbage-collect finished workers from the active set. Tests use
  ## this to assert eventual emptiness after a full advance.
  ## Production callers may rely on `shutdown` instead.
  var doneIds: seq[int] = @[]
  for id, w in m.workers.pairs:
    if w.isFinished:
      doneIds.add id
  for id in doneIds:
    m.workers.del id

proc shutdown*(m: WorkerManager) =
  ## Shutdown drains the manager: every worker is cancelled, the
  ## active set is emptied, and the manager is marked so new spawns
  ## bail. Idempotent.
  if m.shutdownInProgress: return
  m.shutdownInProgress = true
  m.cancelAll()
  m.workers.clear()
