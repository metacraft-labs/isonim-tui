# Workers — background tasks

The M15 worker subsystem provides cooperative background tasks without
forcing apps to manage their own thread pool. Implementation lives at
`src/isonim_tui/worker/`; the top-level module re-exports
`workerMod`, `workerManagerMod`, and `workerDecoratorMod`.

## WorkerManager

Each `TerminalTestHarness` (and each runtime app) owns one
`WorkerManager`. The manager maintains a per-harness set of `Worker`
handles, schedules their `step()` calls on the harness clock, and
shuts them down on dispose.

```nim
type WorkerManager* = ref object
  clock*: TestClock
  workers: seq[Worker]
```

## Worker lifecycle

A `Worker` has five states:

```
wsPending → wsRunning → (wsCompleted | wsCancelled | wsFailed)
```

The state-transition contract is exhaustively tested by
`tests/test_worker_runs_to_completion.nim`,
`tests/test_worker_cancellation.nim`, and
`tests/test_workers_isolated_per_harness.nim`.

## Cooperative cancellation

Cancellation is cooperative — workers must call
`worker.checkCancelled()` periodically. The manager flips the cancel
flag; the next `checkCancelled` raises `WorkerCancelled` and the
worker transitions to `wsCancelled`.

```nim
proc longJob(w: Worker) =
  for i in 0 ..< 1000:
    w.checkCancelled()
    w.scheduleStep(10)  # cooperative yield
    doWorkChunk(i)
  w.complete()
```

## Spawn

Hand a worker function to the manager:

```nim
let handle = h.workerManager.spawn(name = "scan", fn = longJob)
# … later
h.workerManager.cancelGroup("scan")
```

The handle exposes progress, state, and a `bindToDeferredResource`
hook so a downstream signal updates when the worker completes.

## `{.work.}` decorator

The `worker/decorator.nim` macro turns a regular proc into a
worker-aware one — autoinjecting the `Worker` parameter and the
state-machine boilerplate. Convenience layer; not required for
correctness.

## Test isolation

`tests/test_workers_isolated_per_harness.nim` proves two parallel
harnesses see distinct worker sets. This is the foundation for the
M2 `tests/test_harness_isolation_parallel.nim` guarantee that snapshot
tests can run in `--parallel` mode without cross-talk.
