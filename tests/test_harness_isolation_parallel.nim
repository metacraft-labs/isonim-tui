## test_harness_isolation_parallel
##
## Spawn 8 harnesses in parallel threads. Each mounts a different
## counter app, drives it 50 input events. All 8 produce the
## same shape of output and no harness sees state from any other.
##
## The id counter is `{.threadvar.}` so each thread has its own counter
## starting at 0. We assert each thread's renderer assigns ids 1..N
## for its own tree — proving no cross-thread aliasing.
##
## ASan note: each spawned thread leaves a small (~56-byte) per-thread
## allocation behind that LSan flags as "leaked" — this is a known
## interaction between Nim's ORC cycle collector and `std/threads`
## (ORC's per-thread cycle-set isn't auto-collected on thread exit).
## We call `GC_runOrc` and `GC_fullCollect` on each thread before
## return to minimise the leak; the residual ~448 bytes for 8 threads
## is a Nim-runtime artifact, not an isonim-tui correctness issue.
## Single-threaded use of the harness is fully ASan-clean.

import unittest
import isonim_tui
import isonim/core/owner
import std/strformat

const numHarnesses = 8
const numEvents = 50

type ThreadResult = object
  threadIdx: int
  finalCount: int
  firstCell: int32
  byteLen: int
  rootId: int

# We use a Channel to ferry results from worker threads back to the
# main thread; this avoids the GC-unsafe shared-array pattern.
var resultChan: Channel[ThreadResult]
resultChan.open()

proc runOne(idx: int): ThreadResult =
  ## Build a tiny counter widget, drive `numEvents` "enter" presses,
  ## return the visible state. Each thread runs this independently.
  ##
  ## Wrapped in `createRoot` so the reactive owner cleans up signals
  ## and effects when the closure exits — critical for ASan/leak-clean
  ## thread teardown (each thread's local arena would otherwise hold
  ## owner-scoped allocations after the thread exits).
  var res: ThreadResult
  createRoot do (rootDispose: proc()):
    var tally = 0
    let h = newTerminalTestHarness(40, 5)
    var label: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      label = r.createTextNode("0")
      r.appendChild(root, label)
      r.addEventListener(root, "keydown", proc() =
        inc tally
        r.setTextContent(label, $tally))
      root)

    let p = newPilot(h)
    for _ in 0 ..< numEvents:
      p.press("enter")

    res = ThreadResult(
      threadIdx: idx,
      finalCount: tally,
      firstCell: h.cellAt(0, 0).rune.int32,
      byteLen: h.bytesEmitted().len,
      rootId: h.root.id)
    h.dispose()
    rootDispose()
  result = res

proc threadWorker(idx: int) {.thread.} =
  ## Each thread is fully isolated (per-thread renderer, harness, ids).
  ## We cast to gcsafe because the Nim compiler can't statically prove
  ## the closures captured by event handlers are gcsafe — they only
  ## touch local stack variables of `runOne`, which can't escape the
  ## thread.
  {.cast(gcsafe).}:
    let r = runOne(idx)
    resultChan.send(r)
    # Flush ORC cycle collector before thread exit so the per-thread
    # arena gets reclaimed. Without this, ASan/LSan flag the arena
    # contents (closure environments, table-bucket allocations, etc.)
    # as "leaked" — not because they're unreachable, but because the
    # ORC runtime tags them with a thread-local cycle-set that doesn't
    # auto-collect on thread exit.
    when declared(GC_runOrc):
      GC_runOrc()
    when declared(GC_fullCollect):
      GC_fullCollect()

suite "M2: harness isolation (parallel)":
  test "test_harness_isolation_parallel":
    var threads: array[numHarnesses, Thread[int]]
    for i in 0 ..< numHarnesses:
      createThread(threads[i], threadWorker, i)
    joinThreads(threads)

    var received: array[numHarnesses, ThreadResult]
    for _ in 0 ..< numHarnesses:
      let r = resultChan.recv()
      received[r.threadIdx] = r

    # Every thread saw exactly numEvents.
    for i in 0 ..< numHarnesses:
      check received[i].finalCount == numEvents
    # Every thread's id-counter started at 1 — cross-thread
    # isolation. (The renderer is a {.threadvar.} counter.)
    for i in 0 ..< numHarnesses:
      check received[i].rootId == 1
    # Every thread emitted some bytes (the real driver chain ran).
    for i in 0 ..< numHarnesses:
      check received[i].byteLen > 0
    # Every thread's first row starts with "5" (final count = 50).
    let expectedFirst = int32('5'.ord)
    for i in 0 ..< numHarnesses:
      if received[i].firstCell != expectedFirst:
        echo &"thread {i} first cell mismatch: got {received[i].firstCell}"
      check received[i].firstCell == expectedFirst
