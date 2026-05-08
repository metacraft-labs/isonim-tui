## examples/task_app/web/leaves.nim — Layer-1 leaves for the web target.
##
## Concrete platform components for the task-app's high-level view,
## written against the `MockRenderer` from
## `isonim/testing/mock_dom.nim`. `MockRenderer` is the canonical
## headless target for web tests (and the browser `WebRenderer` exposes
## the same proc interface, so the same DSL drives both).
##
## Pattern: each leaf builds a tree of `MockNode` elements with an
## `addEventListener` for the relevant action; activation routes
## through the VM, then triggers a manual re-render via
## `rerender(vm)`. Identical pattern to `tui/leaves.nim` — only the
## widget primitives differ.
##
## To run under `WebRenderer` in a real browser, swap
## `import isonim/testing/mock_dom` for
## `import isonim/web/web_renderer` in the composition root; every
## proc below has a parity overload on `WebRenderer` thanks to the
## RendererBackend concept.

import std/[strutils, tables]

import isonim/core/signals
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
# Layer-1 leaf procs
# ----------------------------------------------------------------------------

proc appShell*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let root = r.createElement("div")
  r.setAttribute(root, "class", "task-app")
  root

proc taskInput*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "task-input")
  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  r.setAttribute(inp, "value", vm.inputText.val)
  s.inputNode = inp
  let addBtn = r.createElement("button")
  r.appendChild(addBtn, r.createTextNode("Add Task"))
  r.addEventListener(addBtn, "click", proc() =
    let text = inp.attributes.getOrDefault("value")
    vm.addTask(text)
    r.setAttribute(inp, "value", "")
    rerender(vm))
  r.appendChild(wrapper, inp)
  r.appendChild(wrapper, addBtn)
  wrapper

proc filterBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "filter-bar")
  s.filterNodes = @[]
  for fm in [fmAll, fmActive, fmCompleted]:
    let btn = r.createElement("button")
    let lbl = $fm
    r.appendChild(btn, r.createTextNode(lbl))
    r.setAttribute(btn, "data-filter", lbl.toLowerAscii)
    if vm.filter.val == fm:
      r.setAttribute(btn, "aria-pressed", "true")
    let captured = fm
    r.addEventListener(btn, "click", proc() =
      vm.setFilter(captured)
      rerender(vm))
    s.filterNodes.add btn
    r.appendChild(wrapper, btn)
  wrapper

proc taskList*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  let node = r.createElement("ul")
  r.setAttribute(node, "class", "task-list")
  s.listNode = node
  s.listWidth = 30
  renderTaskListInto(r, vm, node)
  node

proc summaryBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  let s = leavesFor(vm)
  let node = r.createElement("footer")
  r.setAttribute(node, "class", "task-summary")
  s.summaryNode = node
  renderSummaryInto(r, vm, node)
  node
