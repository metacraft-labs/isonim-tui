## test_snapshot_record_mode
##
## `h.snap(name, recordMode = true)` overwrites the goldens; the next
## run with `recordMode = false` compares clean.
##
## The milestone wording also requires `SNAP_RECORD=1` env-var driven
## re-record. We exercise both: the explicit flag and the env var.

import unittest
import isonim_tui
import std/[os, strutils]

const snapName = "m2_record_mode"

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

suite "M2: snapshot record mode":
  test "test_snapshot_record_mode":
    cleanSnap()

    # Phase 1: record initial golden with "AAAA".
    block phaseOne:
      let h = newTerminalTestHarness(10, 2)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("AAAA"))
        root)
      check h.snap(snapName)
      h.dispose()

    let plaintextPath = snapDir() / snapName / "plaintext.txt"
    let goldenA = readFile(plaintextPath)
    check goldenA.contains("AAAA")

    # Phase 2: re-record with different content via recordMode = true.
    block phaseTwo:
      let h = newTerminalTestHarness(10, 2)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("BBBB"))
        root)
      check h.snap(snapName, recordMode = true)
      h.dispose()

    let goldenB = readFile(plaintextPath)
    check goldenB.contains("BBBB")
    check goldenA != goldenB

    # Phase 3: SNAP_RECORD env var also forces re-record.
    block phaseThree:
      putEnv("SNAP_RECORD", "1")
      let h = newTerminalTestHarness(10, 2)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("CCCC"))
        root)
      check h.snap(snapName)
      h.dispose()
      delEnv("SNAP_RECORD")

    let goldenC = readFile(plaintextPath)
    check goldenC.contains("CCCC")

    # Phase 4: normal run with unchanged golden compares clean.
    block phaseFour:
      let h = newTerminalTestHarness(10, 2)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        r.appendChild(root, r.createTextNode("CCCC"))
        root)
      check h.snap(snapName)
      h.dispose()

    cleanSnap()
