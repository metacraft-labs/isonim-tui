## test_task_app_web_target_compiles — M22 supplementary check.
##
## The TUI repo is the home of M22's deliverables but the Layer-3 VM
## and Layer-2 view are byte-identical between TUI and web. This test
## proves the *web* composition root compiles and exercises the same
## VM through its `MockRenderer` leaves. (A full Playwright run lives
## downstream once `isonim-website/` consumes this example.)
##
## What this guards against:
##   - Layer-3 vm.nim accidentally taking a TUI dependency.
##   - Layer-2 views.nim diverging in a way that compiles under TUI
##     but breaks under MockRenderer (or vice versa).
##   - Action procs in vm.nim relying on signal semantics that work
##     for one renderer but not the other.

import unittest
import std/tables

import isonim/core/signals
import ../examples/task_app/main_web

suite "M22: web composition root drives the same VM":
  test "test_task_app_web_target_compiles":
    let vm = newTaskAppVM()
    let r = MockRenderer()
    let root = buildTaskApp(r, vm)
    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("class") == "task-app"
    # appShell contains: input, filter bar, list, summary.
    check root.children.len == 4

    # Drive via VM — the leaves rebuild on every rerender.
    vm.addTask("First")
    vm.addTask("Second")
    rerender(vm)
    check vm.totalCount == 2

    # Toggle the first task and check the visible list reflects it.
    let firstId = vm.tasks.val[0].id
    vm.toggleTask(firstId)
    rerender(vm)
    check vm.completedCount == 1

    # Filter to active and verify the projection.
    vm.setFilter(fmActive)
    rerender(vm)
    let visible = vm.visibleTasks
    check visible.len == 1
    check visible[0].name == "Second"

    # Filter to completed.
    vm.setFilter(fmCompleted)
    rerender(vm)
    let comp = vm.visibleTasks
    check comp.len == 1
    check comp[0].name == "First"

    # Clearing completed empties the completed view.
    vm.clearCompleted()
    rerender(vm)
    check vm.totalCount == 1
    check vm.visibleTasks.len == 0  # filter is still Completed

    vm.setFilter(fmAll)
    rerender(vm)
    check vm.visibleTasks.len == 1
    check vm.visibleTasks[0].name == "Second"

    # Reset for parallel test isolation.
    resetWebLeaves()
