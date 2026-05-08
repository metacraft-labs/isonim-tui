## test_workers_isolated_per_harness
##
## M15 / Charter §1: each `TerminalTestHarness` owns its own
## `WorkerManager`. Spawning workers on harness A and cancelling
## harness A's manager must not affect harness B's workers. This
## mirrors the parallel-harness isolation guarantee that lets the
## test suite run with `--threads:on` without cross-contamination.

import unittest
import isonim_tui

suite "M15: workers isolated per harness":
  test "test_workers_isolated_per_harness":
    let h1 = newTerminalTestHarness(20, 3)
    let h2 = newTerminalTestHarness(20, 3)
    h1.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    h2.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    # Each manager really is a distinct instance.
    check h1.workerManager != h2.workerManager

    var h1Result = 0
    var h2Result = 0
    let body1 = proc(w: Worker[int]) {.closure.} =
      w.scheduleStep(100.0, proc(w: Worker[int]) =
        if w.checkCancelled: return
        w.complete(1))
    let body2 = proc(w: Worker[int]) {.closure.} =
      w.scheduleStep(100.0, proc(w: Worker[int]) =
        if w.checkCancelled: return
        w.complete(2))

    let w1 = h1.workerManager.spawn[:int](
      body = body1,
      onResult = proc(v: int) {.closure.} = h1Result = v)
    let w2 = h2.workerManager.spawn[:int](
      body = body2,
      onResult = proc(v: int) {.closure.} = h2Result = v)

    check h1.workerManager.count == 1
    check h2.workerManager.count == 1
    check w1.state == wsRunning
    check w2.state == wsRunning

    # Cancel every worker on h1 — h2's worker must keep running.
    h1.workerManager.cancelAll()
    check w1.state == wsCancelled
    check w2.state == wsRunning
    check h2.workerManager.anyRunning

    # Drive h1's clock; w1 stays cancelled (no revival) and w2 is
    # unaffected because it lives on h2's separate clock + manager.
    h1.advance(200)
    check w1.state == wsCancelled
    check h1Result == 0
    check w2.state == wsRunning   ## h2 hasn't advanced yet
    check h2Result == 0

    # Now advance h2 — only w2 completes.
    h2.advance(200)
    check w2.state == wsCompleted
    check h2Result == 2
    check w1.state == wsCancelled
    check h1Result == 0

    # And of course harness disposal drains its own manager only.
    h1.dispose()
    check w2.state == wsCompleted   ## h2 still healthy.
    h2.dispose()

  test "test_each_manager_has_its_own_id_counter":
    ## The manager-scoped handle ids are independent — h1 and h2
    ## both start at 1, no collisions.
    let h1 = newTerminalTestHarness(20, 3)
    let h2 = newTerminalTestHarness(20, 3)
    h1.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))
    h2.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    let body = proc(w: Worker[int]) {.closure.} = w.complete(0)
    discard h1.workerManager.spawn[:int](body = body)
    discard h1.workerManager.spawn[:int](body = body)
    discard h2.workerManager.spawn[:int](body = body)

    check h1.workerManager.nextId == 2
    check h2.workerManager.nextId == 1

    h1.dispose()
    h2.dispose()

  test "test_shutdown_drains_pending_workers":
    ## `shutdown()` cancels every worker and clears the active set.
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var fired = 0
    let body = proc(w: Worker[int]) {.closure.} =
      w.scheduleStep(50.0, proc(w: Worker[int]) =
        if w.checkCancelled: return
        w.complete(0))

    let w1 = h.workerManager.spawn[:int](
      body = body,
      onResult = proc(v: int) {.closure.} = inc fired)
    let w2 = h.workerManager.spawn[:int](
      body = body,
      onResult = proc(v: int) {.closure.} = inc fired)

    check h.workerManager.count == 2
    h.workerManager.shutdown()
    check w1.state == wsCancelled
    check w2.state == wsCancelled
    check h.workerManager.count == 0

    # Even if we somehow advance time, no result comes through.
    h.advance(500)
    check fired == 0

    h.dispose()
