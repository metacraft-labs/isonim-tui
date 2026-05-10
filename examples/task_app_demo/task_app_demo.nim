## examples/task_app_demo/task_app_demo.nim — M27 demo: a smaller
## variant of the M22 task app.
##
## The full M22 task app lives at `isonim-examples/task_app/` (post
## EX-M2) with the complete Layer 1/2/3/4 split for the cross-platform
## story. This
## variant keeps the same core ViewModel pattern but in one file so
## it works as a standalone snapshot demo.
##
## DSL pilot (DM-M0): the renderer-tree construction lives inside a
## single `ui(r):` block. Structural divs use the `tdiv(class=...)`
## form, while M11+ widgets compose via the `w*` wrappers in
## `isonim_tui/dsl/widget_blocks` (see `docs/dsl-pattern.md`).

import std/strutils
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

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
  let cols = h.cols

  let footerBindings = @[
    FooterBinding(key: "n", description: "New task"),
    FooterBinding(key: "x", description: "Toggle done"),
    FooterBinding(key: "q", description: "Quit")]

  result = ui(r):
    tdiv(class = "task-app-demo"):
      wHeader(r, "Tasks", "demo", cols)
      tdiv(class = "task-list"):
        if vm.tasks.len == 0:
          text "(no tasks yet)"
        else:
          for t in vm.tasks:
            tdiv:
              let mark = if t.completed: "[x] " else: "[ ] "
              wLabel(r, mark & t.name)
      wFooter(r, footerBindings, cols, true)

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
