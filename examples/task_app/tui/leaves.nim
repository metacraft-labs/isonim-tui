## examples/task_app/tui/leaves.nim — Layer-1 leaves for the TUI target.
##
## Concrete platform components for the task-app's high-level view.
## Each proc returns a `TerminalNode` ready for `appendChild`. Leaves
## wire input through the VM's actions; the VM's signals never leak
## through to the higher layers.
##
## Pattern: each leaf builds a real M11-M21 widget against the
## `TerminalRenderer`. Activation handlers route through the VM, then
## trigger a manual re-render by walking the tree and rebuilding the
## affected sub-tree. We don't depend on `createRenderEffect` because
## the task-app's mutation pattern is small enough that explicit
## re-renders are simpler and more debuggable than full reactive
## bindings — and the spec only requires byte-identical Layer-3/Layer-2
## across platforms; the leaves are explicitly per-platform.

import isonim/core/signals
import isonim_tui
import ../core/vm

# ----------------------------------------------------------------------------
# Mutable pointers held by the leaves so re-renders can find their
# targets. A single VM owns one each.
# ----------------------------------------------------------------------------

type
  TaskAppLeavesState* = ref object
    ## Per-VM bookkeeping for the TUI target. The composition root
    ## constructs one of these alongside the VM and threads it through
    ## the leaf calls. (We park it on the VM via a lookup table to keep
    ## `views.nim` byte-identical with the web target.)
    inputWidget*: InputWidget
    listNode*: TerminalNode
    summaryNode*: TerminalNode
    filterButtons*: seq[RadioButtonWidget]
    listWidth*: int

# A side-table keyed by VM id is the simplest portable wiring without
# modifying the VM type. Each renderTaskApp call registers one entry;
# leaves resolve via `leavesFor(vm)`.
var tuiLeavesTable {.threadvar.}: seq[tuple[vm: TaskAppVM;
                                            state: TaskAppLeavesState]]

proc leavesFor*(vm: TaskAppVM): TaskAppLeavesState =
  for entry in tuiLeavesTable:
    if entry.vm == vm: return entry.state
  result = TaskAppLeavesState(filterButtons: @[], listWidth: 30)
  tuiLeavesTable.add (vm: vm, state: result)

proc resetTuiLeaves*() =
  ## Reset the per-thread table. Used by tests so VM instances from
  ## prior cases don't leak state into the next case.
  tuiLeavesTable.setLen(0)

# ----------------------------------------------------------------------------
# Re-render helpers (manual reactive — re-build affected subtrees on
# every VM action).
# ----------------------------------------------------------------------------

proc renderTaskListInto(r: TerminalRenderer; vm: TaskAppVM;
                        listNode: TerminalNode; width: int) =
  ## Wipe `listNode`'s children and rebuild from `vm.visibleTasks`.
  while listNode.children.len > 0:
    let c = listNode.children[0]
    r.removeChild(listNode, c)
  let visible = vm.visibleTasks
  if visible.len == 0:
    let row = r.createElement("div")
    let placeholder =
      case vm.filter.val
      of fmAll:       "(no tasks yet)"
      of fmActive:    "(no active tasks)"
      of fmCompleted: "(no completed tasks)"
    r.appendChild(row, r.createTextNode(placeholder))
    r.setStyle(row, "italic", "true")
    r.appendChild(listNode, row)
    return
  for t in visible:
    let row = r.createElement("div")
    r.setAttribute(row, "data-task-id", $t.id)
    let marker = if t.completed: "[x] " else: "[ ] "
    let label = marker & t.name
    let body = (if cellWidth(label) > width:
                  padOrTruncate(label, width)
                else:
                  label)
    r.appendChild(row, r.createTextNode(body))
    if t.completed:
      r.setStyle(row, "italic", "true")
    r.appendChild(listNode, row)

proc renderSummaryInto(r: TerminalRenderer; vm: TaskAppVM;
                       summaryNode: TerminalNode) =
  while summaryNode.children.len > 0:
    let c = summaryNode.children[0]
    r.removeChild(summaryNode, c)
  let row = r.createElement("div")
  let active = vm.activeCount
  let total = vm.totalCount
  let text = $active & " of " & $total & " remaining"
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(summaryNode, row)

proc rerender*(vm: TaskAppVM) =
  ## Re-build any sub-trees that depend on VM state. Called after every
  ## action.
  let s = leavesFor(vm)
  let r = TerminalRenderer()
  if s.listNode != nil:
    renderTaskListInto(r, vm, s.listNode, s.listWidth)
  if s.summaryNode != nil:
    renderSummaryInto(r, vm, s.summaryNode)
  # Sync the filter radio-buttons with the VM's current filter so a
  # programmatic `setFilter` (e.g. from a unit test) reflects in the
  # rendered tree even when the user didn't click a button.
  if s.filterButtons.len == 3:
    let want =
      case vm.filter.val
      of fmAll:       0
      of fmActive:    1
      of fmCompleted: 2
    for i, b in s.filterButtons:
      b.setSelected(i == want)

# ----------------------------------------------------------------------------
# Layer-1 leaf procs — invoked by views.nim
# ----------------------------------------------------------------------------

proc appShell*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Top-level container. Holds the rest of the leaves.
  let root = r.createElement("div")
  r.setAttribute(root, "data-app", "task-app")
  r.setAttribute(root, "class", "task-app")
  root

proc taskInput*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Single-line text field that adds a task on Enter.
  let s = leavesFor(vm)
  let inp = newInput(r,
    value = vm.inputText.val,
    placeholder = "New task...",
    width = 30,
    border = bsRound,
    onChange = proc(newValue: string) =
      vm.setInputText(newValue),
    onSubmit = proc(value: string) =
      vm.addTask(value)
      # After addTask the VM has cleared inputText; mirror that into
      # the widget.
      s.inputWidget.setValue("")
      rerender(vm))
  s.inputWidget = inp
  inp.node

proc filterBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Three-mode filter selector. Uses RadioSet so Enter/Space activates
  ## the focused option.
  let s = leavesFor(vm)
  let rs = newRadioSet(r, onChange = proc(oldId, newId: int;
                                          newValue: string) =
    case newValue
    of "all":       vm.setFilter(fmAll)
    of "active":    vm.setFilter(fmActive)
    of "completed": vm.setFilter(fmCompleted)
    else: discard
    rerender(vm))
  let bAll = newRadioButton(r, "All",       value = "all",
                            selected = vm.filter.val == fmAll)
  let bAct = newRadioButton(r, "Active",    value = "active",
                            selected = vm.filter.val == fmActive)
  let bCom = newRadioButton(r, "Completed", value = "completed",
                            selected = vm.filter.val == fmCompleted)
  rs.addAll [bAll, bAct, bCom]
  s.filterButtons = @[bAll, bAct, bCom]
  rs.node

proc taskList*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## The visible task rows. Rebuild via `rerender`.
  let s = leavesFor(vm)
  let node = r.createElement("div")
  r.setAttribute(node, "class", "task-list")
  s.listNode = node
  s.listWidth = 30
  renderTaskListInto(r, vm, node, s.listWidth)
  node

proc summaryBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## "N of M remaining" footer.
  let s = leavesFor(vm)
  let node = r.createElement("div")
  r.setAttribute(node, "class", "task-summary")
  s.summaryNode = node
  renderSummaryInto(r, vm, node)
  node
