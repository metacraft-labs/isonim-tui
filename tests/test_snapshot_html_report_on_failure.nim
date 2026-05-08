## test_snapshot_html_report_on_failure
##
## A deliberate mismatch produces `tests/snapshots/_report.html` with
## side-by-side panes for each affected format.

import unittest
import isonim_tui
import std/[os, strutils]

const snapName = "m2_html_report_fail"

proc snapDir(): string =
  let cwd = getCurrentDir()
  if dirExists(cwd / "tests" / "snapshots"):
    return cwd / "tests" / "snapshots"
  if dirExists(cwd / "snapshots"):
    return cwd / "snapshots"
  cwd / "tests" / "snapshots"

proc cleanSnap() =
  let d = snapDir() / snapName
  if dirExists(d):
    removeDir(d)
  let report = snapDir() / "_report.html"
  if fileExists(report):
    removeFile(report)

suite "M2: snapshot HTML report on failure":
  test "test_snapshot_html_report_on_failure":
    cleanSnap()

    # Record golden with "hello".
    block recordPhase:
      let h = newTerminalTestHarness(20, 3)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("hello"))
        root)
      check h.snap(snapName)
      h.dispose()

    # Compare against a different render — should fail.
    block comparePhase:
      let h = newTerminalTestHarness(20, 3)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("WORLD"))
        root)
      let matched = h.snap(snapName)
      check not matched

      # The HTML report exists.
      let reportPath = snapDir() / "_report.html"
      check fileExists(reportPath)
      let html = readFile(reportPath)
      check html.contains("FAIL")
      # Side-by-side panes for golden/actual/diff are present.
      check html.contains("Golden")
      check html.contains("Actual")
      check html.contains("Diff")
      h.dispose()

    cleanSnap()
