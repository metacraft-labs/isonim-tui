## examples/task_app/web/leaves.nim — Layer-1 leaves for the web target.
##
## Concrete platform components for the task-app's high-level view,
## written against the `MockRenderer` from
## `isonim/testing/mock_dom.nim`. `MockRenderer` is the canonical
## headless target for web tests (and the browser `WebRenderer` exposes
## the same proc interface, so the same DSL drives both).
##
## DM-M6: each leaf composes its node tree inside a single `ui(r):`
## block. Web-target wrappers are the raw HTML tags from
## `isonim/dsl/ui` (`tdiv`, `span`, `button`, `input`, `ul`, `li`,
## `footer`) — there are no `w*` widget wrappers on the web side
## because `MockRenderer`/`WebRenderer` build trees out of plain DOM
## nodes, not the M11+ widget objects. See `docs/dsl-pattern.md`.
##
## To run under `WebRenderer` in a real browser, swap
## `import isonim/testing/mock_dom` for
## `import isonim/web/web_renderer` in the composition root; every
## proc below has a parity overload on `WebRenderer` thanks to the
## RendererBackend concept.

import std/[strutils, tables]

import isonim/core/signals
import isonim/core/computation  # createRenderEffect (DSL wraps dynamic text/attrs in it)
import isonim/dsl/ui
import isonim/testing/mock_dom
import ../core/vm

type
  TaskAppWebLeavesState* = ref object
    ## Bookkeeping mirror of the TUI `TaskAppLeavesState`.
    inputNode*: MockNode
    listNode*: MockNode
    summaryNode*: MockNode
    filterNodes*: seq[MockNode]
    listWidth*: int

var webLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                            state: TaskAppWebLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppWebLeavesState =
  for entry in webLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppWebLeavesState(filterNodes: @[], listWidth: 30)
  webLeavesTable.add (vm: vm, state: result)

proc resetWebLeaves*() =
  webLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Re-render helpers
# ----------------------------------------------------------------------------

proc renderTaskListInto(r: MockRenderer; vm: TaskAppVM;
                        listNode: MockNode) =
  r.clearChildren(listNode)
  let visible = vm.visibleTasks
  if visible.len == 0:
    let row = r.createElement("li")
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.appendChild(row, r.createTextNode(placeholder))
    r.setStyle(row, "font-style", "italic")
    r.appendChild(listNode, row)
    return
  for t in visible:
    let row = r.createElement("li")
    r.setAttribute(row, "data-task-id", $t.id)
    let toggleBtn = r.createElement("button")
    let marker = if t.completed: "[x]" else: "[ ]"
    r.appendChild(toggleBtn, r.createTextNode(marker))
    let label = r.createElement("span")
    let display =
      if t.completed: t.name & " (done)" else: t.name
    r.appendChild(label, r.createTextNode(display))
    let removeBtn = r.createElement("button")
    r.appendChild(removeBtn, r.createTextNode("x"))
    let taskId = t.id
    r.addEventListener(toggleBtn, "click", proc() =
      vm.toggleTask(taskId))
    r.addEventListener(removeBtn, "click", proc() =
      vm.removeTask(taskId))
    r.appendChild(row, toggleBtn)
    r.appendChild(row, label)
    r.appendChild(row, removeBtn)
    r.appendChild(listNode, row)

proc renderSummaryInto(r: MockRenderer; vm: TaskAppVM;
                       summaryNode: MockNode) =
  r.clearChildren(summaryNode)
  let row = r.createElement("span")
  let active = vm.activeCount
  let total = vm.totalCount
  let text = $active & " of " & $total & " remaining"
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(summaryNode, row)

proc rerender*(vm: TaskAppVM) =
  let s = leavesFor(vm)
  let r = MockRenderer()
  if s.listNode != nil:
    renderTaskListInto(r, vm, s.listNode)
  if s.summaryNode != nil:
    renderSummaryInto(r, vm, s.summaryNode)

# ----------------------------------------------------------------------------
# Closure factories — top-level so loop-variable aliasing can't bite.
# ----------------------------------------------------------------------------

proc makeAddTaskHandler(r: MockRenderer; vm: TaskAppVM;
                        inp: MockNode): proc() =
  result = proc() =
    let text = inp.attributes.getOrDefault("value")
    vm.addTask(text)
    r.setAttribute(inp, "value", "")
    rerender(vm)

proc makeFilterClickHandler(vm: TaskAppVM; fm: FilterMode): proc() =
  result = proc() =
    vm.setFilter(fm)
    rerender(vm)

# ----------------------------------------------------------------------------
# Layer-1 leaf procs
# ----------------------------------------------------------------------------

proc appShell*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  ui(r):
    tdiv(class = "task-app")

proc taskInput*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Text input + add button. The input node and add button are
  ## captured via the DSL `ref =` form; the click handler (built
  ## outside via a factory) reads the input's current value at submit
  ## time. The seeded `value` is set after construction because the
  ## DSL would otherwise wrap a dynamic attribute in
  ## `createRenderEffect` (the explicit re-render path makes the
  ## reactive wrapping unnecessary).
  let s = leavesFor(vm)
  var inpRef, addBtnRef: MockNode
  result = ui(r):
    tdiv(class = "task-input"):
      input(`type` = "text", placeholder = "New task...",
            ref = inpRef)
      button(ref = addBtnRef):
        text "Add Task"
  r.setAttribute(inpRef, "value", vm.inputText.val)
  s.inputNode = inpRef
  r.addEventListener(addBtnRef, "click",
                     makeAddTaskHandler(r, vm, inpRef))

proc filterBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  ## Three filter buttons. Built inside a `ui(r):` block; per-button
  ## click handlers are produced by a top-level factory so the captured
  ## `FilterMode` doesn't alias the loop variable. The selected
  ## `aria-pressed` attribute is set after construction so unselected
  ## buttons carry no attribute (preserves the original byte-shape).
  let s = leavesFor(vm)
  s.filterNodes = @[]
  result = ui(r):
    tdiv(class = "filter-bar"):
      for fm in [fmAll, fmActive, fmCompleted]:
        let lbl = $fm
        button:
          text lbl
  for i, fm in [fmAll, fmActive, fmCompleted]:
    let btn = result.children[i]
    s.filterNodes.add btn
    r.setAttribute(btn, "data-filter", ($fm).toLowerAscii)
    if vm.filter.val == fm:
      r.setAttribute(btn, "aria-pressed", "true")
    r.addEventListener(btn, "click",
                       makeFilterClickHandler(vm, fm))

proc taskList*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  var listRef: MockNode
  result = ui(r):
    ul(class = "task-list", ref = listRef)
  s.listNode = listRef
  s.listWidth = 30
  renderTaskListInto(r, vm, listRef)

proc summaryBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  var summaryRef: MockNode
  result = ui(r):
    footer(class = "task-summary", ref = summaryRef)
  s.summaryNode = summaryRef
  renderSummaryInto(r, vm, summaryRef)
