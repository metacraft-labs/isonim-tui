## TerminalTestHarness — primary user-facing test API for isonim-tui.
##
## Bundles a renderer, a headless driver, a compositor, a virtual clock,
## a per-instance node-id counter, an event log, and the introspection
## API into a single object. Every later milestone tests against this
## harness.
##
## Charter §1: the harness itself is a `ref object` because it owns
## mutable scaffolding (the renderer, driver, compositor, event log,
## focused node) and is shared with the pilot. The data flowing through
## its API stays value-typed.
##
## Synchronous flush contract: `flush()` runs the reactive graph to
## fixpoint, runs layout, runs the compositor, returns only after the
## next paint has committed to the headless driver's screen buffer.

import std/tables

import ../cells
import ../renderer
import ../compositor
import ../drivers/headless_driver
import ../animation/animator as animatorMod
import ../focus/manager as focusMgrMod
import ../worker/manager as workerMgrMod
import ../worker/worker as workerMod
import ./introspection
import ./snapshot/runner as snapRunner

# Use isonim's clock for virtual-time plumbing.
import isonim/core/clock

export animatorMod.Animator, animatorMod.AnimationKey, animatorMod.activeCount,
       animatorMod.activeKeys, animatorMod.isAnimating, animatorMod.cancel,
       animatorMod.cancelAll, animatorMod.tick, animatorMod.waitForIdle,
       animatorMod.animateFloat, animatorMod.currentTime,
       animatorMod.registerAnimation, animatorMod.Animation,
       animatorMod.AnimationStepProc, animatorMod.AnimationCompleteProc

export focusMgrMod.FocusManager, focusMgrMod.FocusChange,
       focusMgrMod.newFocusManager, focusMgrMod.isFocusable,
       focusMgrMod.focusChain, focusMgrMod.setFocus, focusMgrMod.clearFocus,
       focusMgrMod.setFocusByNode, focusMgrMod.focusNext, focusMgrMod.focusPrev,
       focusMgrMod.pushTrap, focusMgrMod.popTrap, focusMgrMod.currentTrap,
       focusMgrMod.handleKey

export workerMgrMod.WorkerManager, workerMgrMod.WorkerHandle,
       workerMgrMod.newWorkerManager, workerMgrMod.spawn, workerMgrMod.add,
       workerMgrMod.cancelAll, workerMgrMod.cancelGroup, workerMgrMod.cancelNode,
       workerMgrMod.shutdown, workerMgrMod.reap, workerMgrMod.count,
       workerMgrMod.allWorkers, workerMgrMod.anyRunning, workerMgrMod.anyPending
export workerMod.WorkerState, workerMod.Worker, workerMod.WorkerBase,
       workerMod.WorkerStateChangeProc, workerMod.newWorker, workerMod.start,
       workerMod.complete, workerMod.fail, workerMod.cancel, workerMod.checkCancelled,
       workerMod.scheduleStep, workerMod.advance, workerMod.updateTotal,
       workerMod.progress, workerMod.isFinished, workerMod.isRunning,
       workerMod.isCancelled, workerMod.bindToDeferredResource,
       workerMod.toDeferredResource

type
  TerminalTestHarness* = ref object
    ## The full bundle. Pilot is constructed lazily (it imports this
    ## module, so we can't reference it inline without a circular dep —
    ## the pilot module forward-declares its type and the harness only
    ## holds an opaque pointer; the pilot module's accessors call back
    ## into harness operations).
    cols*: int
    rows*: int
    renderer*: TerminalRenderer
    driver*: HeadlessDriver
    compositor*: Compositor
    clock*: TestClock
    root*: TerminalNode          ## The mounted root element.
    nextNodeIdCounter*: int      ## Per-harness id counter for snapshot
                                 ## stability across parallel harnesses.
    focusedId*: int              ## 0 means "no focus".
    hoveredId*: int
    eventSeq*: int
    eventLogStorage*: seq[EventLogEntry]
    animator*: Animator          ## M7 — owns the active animation set.
    focusManager*: FocusManager  ## M12 — owns focus chain + traps.
    workerManager*: WorkerManager ## M15 — owns the per-harness worker set.
    disposed*: bool

# ----------------------------------------------------------------------------
# Construction / lifecycle
# ----------------------------------------------------------------------------

proc newTerminalTestHarness*(width, height: int): TerminalTestHarness =
  ## Construct a fresh harness of the given dimensions. The renderer's
  ## thread-local id counter is reset so the first node mounted is id 1.
  ## The harness installs itself as the current `TestClock` so reactive
  ## scheduling routes through its virtual clock.
  resetNodeIds()
  let testClock = newTestClock()
  if currentClock == nil:
    currentClock = testClock
  let h = TerminalTestHarness(
    cols: width, rows: height,
    renderer: TerminalRenderer(),
    driver: newHeadlessDriver(width, height),
    compositor: newCompositor(width, height),
    clock: testClock,
    root: nil,
    nextNodeIdCounter: 0,
    focusedId: 0,
    hoveredId: 0,
    eventSeq: 0,
    eventLogStorage: @[],
    animator: newAnimator(testClock, framesPerSecond = 60),
    focusManager: newFocusManager(),
    workerManager: newWorkerManager(testClock),
    disposed: false)
  h.driver.start()
  resetSnapshotAccumulator()
  h

proc nextNodeId*(h: TerminalTestHarness): int =
  inc h.nextNodeIdCounter
  h.nextNodeIdCounter

proc dispose*(h: TerminalTestHarness) =
  ## Tear down the harness. Idempotent — multiple `dispose()` calls are
  ## safe so test fixtures can defer-call it without bookkeeping.
  if h.disposed: return
  h.disposed = true
  if h.workerManager != nil:
    h.workerManager.shutdown()
  h.driver.stop()
  h.eventLogStorage.setLen(0)
  h.root = nil

# ----------------------------------------------------------------------------
# Mount + flush
# ----------------------------------------------------------------------------

proc flush*(h: TerminalTestHarness) =
  ## Run the reactive graph to fixpoint, layout, and compositor; pump
  ## the resulting buffer through the driver. The harness uses the
  ## existing isonim reactive runtime — the only "graph fixpoint" work
  ## here is delegating to the renderer's effects, which run
  ## synchronously when their dependencies update. Pilot actions invoke
  ## `flush()` after each input event.
  if h.disposed: return
  if h.root == nil: return
  h.compositor.paint(h.root, h.driver)

proc mount*(h: TerminalTestHarness;
            buildProc: proc(r: TerminalRenderer): TerminalNode) =
  ## Build the root tree using the provided closure and paint the
  ## initial frame. The closure receives the renderer so application
  ## code can call `r.createElement(...)` etc. directly. Subsequent
  ## flushes use the same root.
  resetNodeIds()
  h.root = buildProc(h.renderer)
  h.flush()

proc mountTree*(h: TerminalTestHarness; root: TerminalNode) =
  ## Variant for callers that have already constructed a tree (e.g.
  ## via the DSL). Just sets `h.root` and paints.
  h.root = root
  h.flush()

# ----------------------------------------------------------------------------
# Time / virtual clock
# ----------------------------------------------------------------------------

proc advance*(h: TerminalTestHarness; ms: int) =
  ## Move the virtual clock forward by `ms` milliseconds. Scheduled
  ## callbacks fire in chronological order; flush is invoked once at
  ## the end so any state mutations they triggered are reflected on
  ## screen.
  h.clock.advance(ms.float64)
  h.flush()

proc advanceMs*(h: TerminalTestHarness; ms: float64) =
  ## Float variant of `advance`. Useful for the M7 animator's
  ## sub-millisecond frame ticks (e.g. 16.6667 ms at 60 Hz).
  h.clock.advance(ms)
  h.flush()

# ----------------------------------------------------------------------------
# Resize
# ----------------------------------------------------------------------------

proc resize*(h: TerminalTestHarness; cols, rows: int) =
  h.cols = cols
  h.rows = rows
  h.driver.resize(cols, rows)
  h.compositor.resize(cols, rows)
  h.flush()

# ----------------------------------------------------------------------------
# Event log
# ----------------------------------------------------------------------------

proc recordEvent*(h: TerminalTestHarness; targetId: int;
                  eventType: string) =
  inc h.eventSeq
  h.eventLogStorage.add newEventLogEntry(h.eventSeq, targetId, eventType)

proc eventLog*(h: TerminalTestHarness): seq[EventLogEntry] =
  h.eventLogStorage

proc lastEvent*(h: TerminalTestHarness): EventLogEntry =
  if h.eventLogStorage.len == 0:
    return EventLogEntry(seqNumber: 0, targetId: 0, eventType: "")
  return h.eventLogStorage[^1]

# ----------------------------------------------------------------------------
# Tree introspection
# ----------------------------------------------------------------------------

proc findById*(h: TerminalTestHarness; id: string): TerminalNode =
  introspection.findById(h.root, id)

proc findByClass*(h: TerminalTestHarness; cls: string): seq[TerminalNode] =
  introspection.findByClass(h.root, cls)

proc findByTag*(h: TerminalTestHarness; tag: string): seq[TerminalNode] =
  introspection.findByTag(h.root, tag)

proc findAll*(h: TerminalTestHarness;
              predicate: proc(n: TerminalNode): bool): seq[TerminalNode] =
  introspection.findAll(h.root, predicate)

proc parentOf*(h: TerminalTestHarness; node: TerminalNode): TerminalNode =
  introspection.parent(node)

proc childrenOf*(h: TerminalTestHarness; node: TerminalNode): seq[TerminalNode] =
  introspection.children(node)

proc descendantsOf*(h: TerminalTestHarness;
                   node: TerminalNode): seq[TerminalNode] =
  introspection.descendants(node)

proc ancestorsOf*(h: TerminalTestHarness;
                 node: TerminalNode): seq[TerminalNode] =
  introspection.ancestors(node)

# ----------------------------------------------------------------------------
# Computed state
# ----------------------------------------------------------------------------

proc computedStyle*(h: TerminalTestHarness;
                   node: TerminalNode): ComputedStyle =
  introspection.computedStyleFor(node)

proc layoutRegion*(h: TerminalTestHarness;
                  node: TerminalNode): LayoutRegion =
  introspection.layoutRegionForNode(h.compositor, h.root, node)

proc scrollOffset*(h: TerminalTestHarness;
                  node: TerminalNode): tuple[row, col: int] =
  ## Placeholder until M3 lands real scrolling. Returns (0, 0).
  (row: 0, col: 0)

proc focusedNode*(h: TerminalTestHarness): TerminalNode =
  if h.focusedId == 0 or h.root == nil: return nil
  proc walk(n: TerminalNode): TerminalNode =
    if n == nil: return nil
    if n.id == h.focusedId: return n
    for c in n.children:
      let m = walk(c)
      if m != nil: return m
    return nil
  walk(h.root)

# ----------------------------------------------------------------------------
# Focus navigation (M12)
# ----------------------------------------------------------------------------

proc focusNext*(h: TerminalTestHarness): FocusChange =
  ## Move focus to the next focusable node in tree order. Wraps from
  ## last → first. Updates `h.focusedId` to match the focus manager.
  result = h.focusManager.focusNext(h.root)
  h.focusedId = h.focusManager.focusedId
  if result.oldId != result.newId:
    if result.oldId != 0: h.recordEvent(result.oldId, "blur")
    if result.newId != 0: h.recordEvent(result.newId, "focus")
  h.flush()

proc focusPrev*(h: TerminalTestHarness): FocusChange =
  result = h.focusManager.focusPrev(h.root)
  h.focusedId = h.focusManager.focusedId
  if result.oldId != result.newId:
    if result.oldId != 0: h.recordEvent(result.oldId, "blur")
    if result.newId != 0: h.recordEvent(result.newId, "focus")
  h.flush()

proc focusChain*(h: TerminalTestHarness): seq[int] =
  ## Snapshot of the current focus chain (focusable node ids in DFS
  ## tree order under the active trap).
  h.focusManager.focusChain(h.root)

proc setFocus*(h: TerminalTestHarness; node: TerminalNode): FocusChange =
  ## Programmatic focus mutation that goes through the focus manager
  ## (so listeners + traps are honoured). Mirrors `pilot.focus(node)`
  ## but without firing a synthetic input-driver event.
  result = h.focusManager.setFocusByNode(h.root, node)
  h.focusedId = h.focusManager.focusedId
  if result.oldId != result.newId:
    if result.oldId != 0: h.recordEvent(result.oldId, "blur")
    if result.newId != 0: h.recordEvent(result.newId, "focus")
  h.flush()

proc isFocused*(h: TerminalTestHarness; node: TerminalNode): bool =
  node != nil and node.id == h.focusedId

proc isHovered*(h: TerminalTestHarness; node: TerminalNode): bool =
  node != nil and node.id == h.hoveredId

proc isDisabled*(h: TerminalTestHarness; node: TerminalNode): bool =
  node != nil and node.attributes.getOrDefault("disabled") != ""

proc eventListenerCount*(h: TerminalTestHarness; node: TerminalNode;
                         event: string): int =
  introspection.eventListenerCount(node, event)

# ----------------------------------------------------------------------------
# Render-state queries
# ----------------------------------------------------------------------------

proc screenBuffer*(h: TerminalTestHarness): ScreenBuffer =
  h.driver.buffer

proc cellAt*(h: TerminalTestHarness; row, col: int): Cell =
  h.driver.cellAt(row, col)

proc dirtyRegions*(h: TerminalTestHarness): seq[CellRegion] =
  h.compositor.lastDirty

proc stripCacheStats*(h: TerminalTestHarness): StripCacheStats =
  ## Snapshot the compositor's strip cache hit / miss counters. With
  ## M8 the compositor maintains a per-node cache keyed by the input
  ## hash; this accessor surfaces the running totals so tests can
  ## assert e.g. "≥ 95% hit rate after a one-row scroll".
  h.compositor.stats()

proc bytesEmitted*(h: TerminalTestHarness): string =
  h.driver.bytesEmitted

proc clearBytesEmitted*(h: TerminalTestHarness) =
  h.driver.clearBytes()

# ----------------------------------------------------------------------------
# dumpTree
# ----------------------------------------------------------------------------

proc dumpTree*(h: TerminalTestHarness): string =
  introspection.dumpTree(h.compositor, h.root)

# ----------------------------------------------------------------------------
# Snapshot
# ----------------------------------------------------------------------------

proc snap*(h: TerminalTestHarness; name: string;
           recordMode: bool = false): bool {.discardable.} =
  ## Record or compare the snapshot under `tests/snapshots/<name>/`.
  ## Returns true on match (or always true when recording). On
  ## mismatch the HTML report is written to `tests/snapshots/_report.html`.
  let inputs = SnapInputs(
    name: name,
    buffer: h.driver.buffer,
    root: h.root,
    compositor: h.compositor,
    focusedId: h.focusedId)
  return snapRunner.snapImpl(inputs, recordMode)

# ----------------------------------------------------------------------------
# Pilot — surface area below.
# ----------------------------------------------------------------------------

# The pilot lives in its own module to keep the harness focused on
# state ownership. The pilot calls back into harness procs above;
# nothing here references the pilot type directly.
