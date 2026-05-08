## test_task_app_tui_snapshot_five_states — M22 mandatory test.
##
## Drives the cross-platform task-app TUI through five canonical
## states and records a six-format snapshot for each. The snapshots
## act as goldens for the next run; mismatches fail the test and
## emit `tests/snapshots/_report.html`.
##
## States (each a separate snapshot bundle):
##   1. m22_task_app_empty                  — no tasks, filter=All
##   2. m22_task_app_three_tasks            — three tasks, none done
##   3. m22_task_app_one_completed          — three tasks, first toggled
##   4. m22_task_app_filter_active          — same VM, filter=Active
##   5. m22_task_app_filter_completed       — same VM, filter=Completed
##
## All snapshots go through the real harness → real compositor → real
## headless driver pipeline. No mocks, no rendering shortcuts.

import unittest
import isonim_tui

import ../examples/task_app/main_tui

suite "M22: task-app TUI snapshot coverage":
  test "test_task_app_tui_snapshot_five_states":
    let vm = newTaskAppVM()
    let h = newTerminalTestHarness(48, 12)
    discard runTaskApp(h, vm)

    # State 1: empty.
    h.flush()
    discard h.snap("m22_task_app_empty")

    # State 2: three tasks.
    vm.addTask("Buy milk")
    vm.addTask("Write specs")
    vm.addTask("Review PR")
    rerender(vm)
    h.flush()
    discard h.snap("m22_task_app_three_tasks")
    check vm.totalCount == 3
    check vm.activeCount == 3

    # State 3: complete the first task.
    let firstId = vm.tasks.val[0].id
    vm.toggleTask(firstId)
    rerender(vm)
    h.flush()
    discard h.snap("m22_task_app_one_completed")
    check vm.activeCount == 2
    check vm.completedCount == 1

    # State 4: filter to Active — first task hidden.
    vm.setFilter(fmActive)
    rerender(vm)
    h.flush()
    discard h.snap("m22_task_app_filter_active")
    check vm.visibleTasks.len == 2
    for t in vm.visibleTasks:
      check not t.completed

    # State 5: filter to Completed — only first task visible.
    vm.setFilter(fmCompleted)
    rerender(vm)
    h.flush()
    discard h.snap("m22_task_app_filter_completed")
    check vm.visibleTasks.len == 1
    check vm.visibleTasks[0].completed

    h.dispose()
