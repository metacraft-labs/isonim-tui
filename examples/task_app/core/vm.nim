## examples/task_app/core/vm.nim — Layer-3 ViewModel (pure logic).
##
## Cross-platform task-app state. This file is byte-identical between
## the TUI and web targets (and any future targets — Cocoa, Android,
## GPUI). It imports nothing from the platform layers and nothing from
## the renderer surface — only `isonim/core/signals` for reactive
## primitives.
##
## The VM is the *single source of truth*. Every higher layer reads
## from it and routes user actions back through it. Layer 2 turns the
## VM into a tree; Layer 1 picks the platform-specific widgets that
## render that tree; Layer 4 wires it all up.
##
## Cross-platform architecture:
## `codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`.

import isonim/core/signals

type
  FilterMode* {.pure.} = enum
    fmAll = "All"
    fmActive = "Active"
    fmCompleted = "Completed"

  Task* = object
    ## A single task. Value type — copied freely, no shared identity
    ## beyond `id`. The id is assigned by the VM at `addTask` time and
    ## is monotonic per VM instance (collisions across VM instances are
    ## allowed because tasks never travel between VMs).
    id*: int
    name*: string
    completed*: bool

  TaskAppVM* = ref object
    ## The shared ViewModel for the task app. Exposes three signals so
    ## reactive views can subscribe to mutations:
    ##
    ##   * `tasks`      — the full task list, in insertion order
    ##   * `filter`     — which subset to render (All / Active / Completed)
    ##   * `inputText`  — the current draft text in the "new task" field
    ##
    ## Every action proc below mutates one or more of these signals and
    ## the platform leaves observe via `createRenderEffect`. The VM
    ## itself is renderer-agnostic and contains no DOM/widget references.
    tasks*: Signal[seq[Task]]
    filter*: Signal[FilterMode]
    inputText*: Signal[string]
    nextId: int

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTaskAppVM*(): TaskAppVM =
  ## Construct a fresh VM with empty task list, "All" filter, empty
  ## draft text, and id counter starting at 1.
  TaskAppVM(
    tasks: createSignal[seq[Task]](@[]),
    filter: createSignal[FilterMode](fmAll),
    inputText: createSignal[string](""),
    nextId: 1)

# ----------------------------------------------------------------------------
# Actions (mutate the VM through these — never poke the signals directly
# from outside the VM module).
# ----------------------------------------------------------------------------

proc addTask*(vm: TaskAppVM; name: string) =
  ## Append a new task with the given name. Empty / whitespace-only
  ## names are ignored. After insertion, `inputText` is cleared.
  var trimmed = name
  while trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t'):
    trimmed = trimmed[1 ..< trimmed.len]
  while trimmed.len > 0 and (trimmed[^1] == ' ' or trimmed[^1] == '\t'):
    trimmed = trimmed[0 ..< trimmed.len - 1]
  if trimmed.len == 0: return
  var ts = vm.tasks.val
  ts.add Task(id: vm.nextId, name: trimmed, completed: false)
  inc vm.nextId
  vm.tasks.val = ts
  vm.inputText.val = ""

proc toggleTask*(vm: TaskAppVM; id: int) =
  ## Flip the `completed` flag on the task with the given id. No-op
  ## when the id is unknown (defensive — a stale toggle from a removed
  ## row should not crash).
  var ts = vm.tasks.val
  var changed = false
  for i in 0 ..< ts.len:
    if ts[i].id == id:
      ts[i].completed = not ts[i].completed
      changed = true
      break
  if changed:
    vm.tasks.val = ts

proc removeTask*(vm: TaskAppVM; id: int) =
  ## Drop the task with the given id. No-op when unknown.
  var ts = vm.tasks.val
  var idx = -1
  for i in 0 ..< ts.len:
    if ts[i].id == id:
      idx = i
      break
  if idx >= 0:
    ts.delete(idx)
    vm.tasks.val = ts

proc clearCompleted*(vm: TaskAppVM) =
  ## Drop every completed task in one batch.
  var ts = vm.tasks.val
  var kept: seq[Task] = @[]
  for t in ts:
    if not t.completed:
      kept.add t
  vm.tasks.val = kept

proc setFilter*(vm: TaskAppVM; m: FilterMode) =
  vm.filter.val = m

proc setInputText*(vm: TaskAppVM; text: string) =
  vm.inputText.val = text

# ----------------------------------------------------------------------------
# Derived state (read-only views over signals; not memos because the
# JS backend's memo plumbing isn't required here — every consumer
# already subscribes to the underlying signals).
# ----------------------------------------------------------------------------

proc visibleTasks*(vm: TaskAppVM): seq[Task] =
  ## The subset of tasks matching the current filter. Reads `tasks` and
  ## `filter` so callers inside a `createRenderEffect` re-run when
  ## either changes.
  let f = vm.filter.val
  let ts = vm.tasks.val
  case f
  of fmAll: ts
  of fmActive:
    var keep: seq[Task] = @[]
    for t in ts:
      if not t.completed: keep.add t
    keep
  of fmCompleted:
    var keep: seq[Task] = @[]
    for t in ts:
      if t.completed: keep.add t
    keep

proc activeCount*(vm: TaskAppVM): int =
  var n = 0
  for t in vm.tasks.val:
    if not t.completed: inc n
  n

proc completedCount*(vm: TaskAppVM): int =
  var n = 0
  for t in vm.tasks.val:
    if t.completed: inc n
  n

proc totalCount*(vm: TaskAppVM): int =
  vm.tasks.val.len

# ----------------------------------------------------------------------------
# Snapshot — used by tests to assert the VM reached an expected state
# without depending on the rendered tree.
# ----------------------------------------------------------------------------

type
  VMSnapshot* = object
    ## Plain-value snapshot of the VM for golden comparisons.
    tasks*: seq[Task]
    filter*: FilterMode
    inputText*: string

proc snapshot*(vm: TaskAppVM): VMSnapshot =
  VMSnapshot(
    tasks: vm.tasks.val,
    filter: vm.filter.val,
    inputText: vm.inputText.val)
