## test_worker_runs_to_completion
##
## M15: a worker that "sleeps" 100ms (virtual clock) and returns a
## value:
##   1. starts in `wsPending`, transitions through `wsRunning` to
##      `wsCompleted`;
##   2. its `res` field holds the returned value once finished;
##   3. the spawning widget receives the result via the `onResult`
##      signal-equivalent (the manager's typed result hand-off).

import unittest
import isonim_tui

suite "M15: worker runs to completion":
  test "test_worker_runs_to_completion":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var observedStates: seq[WorkerState] = @[]
    var widgetReceived: int = 0
    var onResultFired: int = 0

    # The "spawning widget" — captures the typed result via
    # `onResult` (the manager's signal hand-off).
    let receiveResult = proc(value: int) {.closure.} =
      widgetReceived = value
      inc onResultFired

    let observe = proc(s: WorkerState) {.closure.} =
      observedStates.add s

    # Body: sleep 100ms (virtual clock) then complete with 42.
    let body = proc(w: Worker[int]) {.closure.} =
      w.scheduleStep(100.0, proc(w: Worker[int]) =
        if w.checkCancelled: return
        w.complete(42))

    let w = h.workerManager.spawn[:int](
      body = body,
      name = "loadAnswer",
      onStateChange = observe,
      onResult = receiveResult)

    # Pending → Running fires synchronously inside `spawn`'s
    # auto-start. The body has already armed its first
    # `scheduleStep`.
    check w.state == wsRunning
    check observedStates == @[wsPending, wsRunning]
    check w.res == 0           ## still default — body hasn't run.
    check onResultFired == 0

    # Advance virtual time by 50ms — too soon, callback hasn't
    # fired.
    h.advance(50)
    check w.state == wsRunning
    check onResultFired == 0

    # Advance the rest of the way — callback fires, worker
    # transitions to completed and onResult delivers the value.
    h.advance(60)
    check w.state == wsCompleted
    check w.res == 42
    check widgetReceived == 42
    check onResultFired == 1
    check observedStates == @[wsPending, wsRunning, wsCompleted]
    check w.isFinished
    check not w.isRunning
    check not w.isCancelled

    h.dispose()

  test "test_worker_complete_immediately":
    ## Sanity: a worker that completes inside its body (no
    ## `scheduleStep`) reaches `wsCompleted` synchronously.
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var got: string = ""
    let body = proc(w: Worker[string]) {.closure.} =
      w.complete("hi")
    let w = h.workerManager.spawn[:string](
      body = body,
      onResult = proc(v: string) {.closure.} = got = v)
    check w.state == wsCompleted
    check w.res == "hi"
    check got == "hi"
    h.dispose()

  test "test_worker_error_transitions_to_errored":
    ## A body that raises an exception transitions to `wsErrored`
    ## and the error message is preserved.
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      r.createElement("div"))

    var resultFired = 0
    let body = proc(w: Worker[int]) {.closure.} =
      raise newException(ValueError, "boom")
    let w = h.workerManager.spawn[:int](
      body = body,
      onResult = proc(v: int) {.closure.} = inc resultFired)
    check w.state == wsErrored
    check w.error == "boom"
    check resultFired == 0   ## onResult never fires on error
    h.dispose()
