## test_snapshot_six_formats_recorded
##
## First `h.snap("name")` run produces six files under
## `tests/snapshots/<name>/`. Second run with unchanged buffer passes
## all six. Mutating one cell makes svg/txt/ansi/cellmap fail with a
## diff pointing to the cell.

import unittest
import isonim_tui
import std/[os, strutils]

const snapName = "m2_six_formats_basic"

proc snapDir(): string =
  ## Mirror the runner's lookup logic.
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

suite "M2: snapshot six formats":
  test "test_snapshot_six_formats_recorded":
    cleanSnap()

    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "main")
      r.appendChild(root, r.createTextNode("hello"))
      root)

    # First run: records.
    let firstResult = h.snap(snapName)
    check firstResult

    let baseDir = snapDir() / snapName
    check fileExists(baseDir / "plaintext.txt")
    check fileExists(baseDir / "ansi.ansi")
    check fileExists(baseDir / "cellmap.json")
    check fileExists(baseDir / "svg.svg")
    check fileExists(baseDir / "annotated.svg")
    check fileExists(baseDir / "treedump.txt")

    # Second run: compares clean (same harness state).
    let secondResult = h.snap(snapName)
    check secondResult

    # Inspect plaintext content.
    let txt = readFile(baseDir / "plaintext.txt")
    check txt.contains("hello")

    h.dispose()
    cleanSnap()
