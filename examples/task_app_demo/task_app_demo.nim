## examples/task_app_demo/task_app_demo.nim — M27 demo: a smaller
## variant of the M22 task app.
##
## The full M22 task app lives at `examples/task_app/` with the
## complete Layer 1/2/3/4 split for the cross-platform story. This
## variant keeps the same core ViewModel pattern but in one file so
## it works as a standalone snapshot demo.

import std/strutils
import isonim_tui

# ----------------------------------------------------------------------------
# ViewModel
# ----------------------------------------------------------------------------

type
  Task* = object
    id*: int
    name*: string
    completed*: bool

  TaskAppDemoVM* = ref object
    tasks*: seq[Task]
    nextId*: int

proc newTaskAppDemoVM*(): TaskAppDemoVM =
  TaskAppDemoVM(tasks: @[], nextId: 1)

proc addTask*(vm: TaskAppDemoVM; name: string) =
  let trimmed = name.strip()
  if trimmed.len == 0: return
  vm.tasks.add Task(id: vm.nextId, name: trimmed, completed: false)
  inc vm.nextId

proc toggleTask*(vm: TaskAppDemoVM; id: int) =
  for i in 0 ..< vm.tasks.len:
    if vm.tasks[i].id == id:
      vm.tasks[i].completed = not vm.tasks[i].completed
      break

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildTaskAppDemoApp*(h: TerminalTestHarness; vm: TaskAppDemoVM):
                         TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.setAttribute(root, "class", "task-app-demo")

  let header = newHeader(r, title = "Tasks", subtitle = "demo",
                         width = h.cols)
  r.appendChild(root, header.node)

  # Task list rows.
  let listBox = r.createElement("div")
  r.setAttribute(listBox, "class", "task-list")
  if vm.tasks.len == 0:
    r.appendChild(listBox, r.createTextNode("(no tasks yet)"))
  else:
    for t in vm.tasks:
      let row = r.createElement("div")
      let mark = if t.completed: "[x] " else: "[ ] "
      let lbl = newLabel(r, mark & t.name)
      r.appendChild(row, lbl.node)
      r.appendChild(listBox, row)
  r.appendChild(root, listBox)

  let footer = newFooter(r,
    bindings = @[
      FooterBinding(key: "n", description: "New task"),
      FooterBinding(key: "x", description: "Toggle done"),
      FooterBinding(key: "q", description: "Quit")],
    width = h.cols, compact = true)
  r.appendChild(root, footer.node)

  root

proc mountTaskAppDemo*(h: TerminalTestHarness): TaskAppDemoVM =
  let vm = newTaskAppDemoVM()
  vm.addTask("Write docs")
  vm.addTask("Ship M27")
  vm.addTask("Celebrate")
  vm.toggleTask(1)
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildTaskAppDemoApp(h, vm))
  vm

when isMainModule:
  let h = newTerminalTestHarness(40, 12)
  let vm = mountTaskAppDemo(h)
  echo "Task app demo: ", vm.tasks.len, " tasks."
  h.dispose()
