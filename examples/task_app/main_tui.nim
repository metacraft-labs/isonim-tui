## examples/task_app/main_tui.nim — Layer-4 composition root for the
## TUI target.
##
## Order matters: the leaves module exports the leaf names (`appShell`,
## `taskInput`, …) used by `core/views.nim`; the `include` of
## `core/views.nim` resolves those names against the imported leaves
## here.

import isonim_tui

import ./core/vm
import ./tui/leaves

export vm, leaves

include ./core/views

proc buildTaskApp*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  ## Convenience wrapper exported for tests. Mirrors what `runApp`
  ## would do in a production driver: build the tree, return the root.
  renderTaskApp(r, vm)

proc runTaskApp*(h: TerminalTestHarness; vm: TaskAppVM): TerminalNode =
  ## Mount the task app into a `TerminalTestHarness` and return the
  ## root node. Used by tests + by an interactive entry point.
  resetTuiLeaves()
  var rootRef: TerminalNode
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    rootRef = buildTaskApp(r, vm)
    rootRef)
  rootRef

when isMainModule:
  let appVm = newTaskAppVM()
  let h = newTerminalTestHarness(60, 12)
  discard runTaskApp(h, appVm)
  echo "Task app TUI mounted (", h.cols, "x", h.rows, ")."
  echo "Tasks: ", totalCount(appVm)
  h.dispose()
