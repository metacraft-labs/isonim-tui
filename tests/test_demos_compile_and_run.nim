## test_demos_compile_and_run — M27 mandatory test.
##
## For each `examples/<name>/` shipped in the M27 release, this test:
##   1. Compiles the example (the file ships standalone — this test
##      just `import`s the public builder, so the compile happens by
##      virtue of being part of the test's compilation graph).
##   2. Mounts it under `TerminalTestHarness`.
##   3. Drives a recorded scenario.
##   4. Snapshots the result against
##      `tests/snapshots/examples/<name>/`.
##
## The snapshot harness records on first run (or with `SNAP_RECORD=1`),
## diffs against the golden on subsequent runs.

import unittest
import isonim_tui

import ../examples/calculator/calculator
import ../examples/dictionary/dictionary
import ../examples/code_browser/code_browser
import ../examples/log_viewer/log_viewer
import ../examples/system_monitor/system_monitor
import ../examples/markdown_viewer/markdown_viewer
import ../examples/task_app_demo/task_app_demo
import ../examples/datatable_demo/datatable_demo

suite "M27: examples/ apps compile, mount, snapshot":

  test "test_demos_calculator":
    let h = newTerminalTestHarness(40, 18)
    let vm = mountCalculator(h)
    # Recorded scenario: type 2+3=
    vm.digit(2)
    vm.setOp(opAdd)
    vm.digit(3)
    vm.equals()
    discard h.renderer  # keep compiler happy
    h.flush()
    check vm.display == "5"
    discard h.snap("examples/calculator")
    h.dispose()

  test "test_demos_dictionary":
    let h = newTerminalTestHarness(60, 20)
    let vm = mountDictionary(h)
    # Recorded scenario: filter to a substring.
    vm.setQuery("a")
    h.flush()
    check vm.results.len > 0
    discard h.snap("examples/dictionary")
    h.dispose()

  test "test_demos_code_browser":
    let h = newTerminalTestHarness(80, 20)
    let vm = mountCodeBrowser(h)
    h.flush()
    check vm.selectedPath.len > 0
    discard h.snap("examples/code_browser")
    h.dispose()

  test "test_demos_log_viewer":
    let h = newTerminalTestHarness(80, 20)
    let vm = mountLogViewer(h)
    h.flush()
    check vm.lines.len > 0
    discard h.snap("examples/log_viewer")
    h.dispose()

  test "test_demos_system_monitor":
    let h = newTerminalTestHarness(60, 22)
    mountSystemMonitor(h)
    h.flush()
    discard h.snap("examples/system_monitor")
    h.dispose()

  test "test_demos_markdown_viewer":
    let h = newTerminalTestHarness(60, 24)
    mountMarkdownViewer(h)
    h.flush()
    discard h.snap("examples/markdown_viewer")
    h.dispose()

  test "test_demos_task_app_demo":
    let h = newTerminalTestHarness(40, 12)
    let vm = mountTaskAppDemo(h)
    h.flush()
    check vm.tasks.len == 3
    discard h.snap("examples/task_app_demo")
    h.dispose()

  test "test_demos_datatable_demo":
    let h = newTerminalTestHarness(40, 18)
    mountDataTableDemo(h)
    h.flush()
    discard h.snap("examples/datatable_demo")
    h.dispose()
