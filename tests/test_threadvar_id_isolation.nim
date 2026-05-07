## test_threadvar_id_isolation
##
## Spawns 4 threads, each constructing 100 elements via separate
## `TerminalRenderer` instances. Asserts no two elements have the same
## id within a single thread, and that ids form a contiguous range
## starting at 1 per thread (per the M0 spec test definition).
##
## Why this matters: prior to M0 the demo renderer's
## `nextTerminalNodeId` was a plain `var` global; under threads it
## raced. The new isonim_tui renderer mirrors `mock_dom.nim:40`'s
## `{.threadvar.}` declaration so every thread sees a fresh,
## monotonically-increasing counter. Same story for the renamed
## `terminal_demo.nim`.
##
## We use a thread-safe `Channel` to ferry results back so the worker
## body is GC-safe. No mocks — every element is a real
## `TerminalRenderer.createElement` call exercising the real id counter.

import unittest
import std/[sets, algorithm]

import isonim_tui/renderer

const
  ThreadCount = 4
  ElementsPerThread = 100

type
  WorkerArg = tuple
    idx: int
  WorkerResult = tuple
    idx: int
    ids: seq[int]

# A *single* channel for the lifetime of the process; opening / closing
# repeatedly (one channel per call) trips a SIGSEGV in the orc runtime
# (the first close frees the channel state but the underlying
# `getChannel` still tracks its handle). Threads send their batch and
# the main thread drains it before the next batch starts, so the queue
# is always empty between batches.
var resultsChan: Channel[WorkerResult]
resultsChan.open()

proc threadEntry(arg: WorkerArg) {.thread.} =
  ## Construct ElementsPerThread real TerminalRenderer elements on this
  ## thread. The `{.threadvar.}` counter starts at 0 per thread, so we
  ## expect ids 1..ElementsPerThread.
  resetNodeIds()
  let r = TerminalRenderer()
  var ids: seq[int] = @[]
  for i in 0 ..< ElementsPerThread:
    let n = r.createElement("div")
    ids.add n.id
  resultsChan.send((idx: arg.idx, ids: ids))

proc runWorkers(): array[ThreadCount, seq[int]] =
  var threads: array[ThreadCount, Thread[WorkerArg]]
  for i in 0 ..< ThreadCount:
    createThread(threads[i], threadEntry, (idx: i))
  joinThreads(threads)
  for _ in 0 ..< ThreadCount:
    let r = resultsChan.recv()
    result[r.idx] = r.ids

suite "Threadvar id isolation":
  test "test_4_threads_x_100_elements_no_collision_within_thread":
    let results = runWorkers()
    for tIdx in 0 ..< ThreadCount:
      var seen: HashSet[int]
      for id in results[tIdx]:
        check id notin seen
        seen.incl id
      check seen.len == ElementsPerThread

  test "test_ids_form_contiguous_range_starting_from_1":
    let results = runWorkers()
    for tIdx in 0 ..< ThreadCount:
      let ids = results[tIdx]
      check ids.len == ElementsPerThread
      var sortedIds = ids
      sortedIds.sort(system.cmp[int])
      for i in 0 ..< ElementsPerThread:
        check sortedIds[i] == i + 1

  test "test_main_thread_counter_unaffected_by_workers":
    ## The main thread has its own counter. After workers finish, the
    ## main thread should still see whatever it had before — verifies
    ## the counter is genuinely per-thread, not just monotonic.
    resetNodeIds()
    let r = TerminalRenderer()
    discard r.createElement("a")
    discard r.createElement("b")
    discard r.createElement("c")

    discard runWorkers()

    # Main-thread counter is still at 3 — our 4th element gets id 4.
    let nextNode = r.createElement("d")
    check nextNode.id == 4
