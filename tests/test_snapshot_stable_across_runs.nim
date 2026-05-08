## test_snapshot_stable_across_runs
##
## Running the same test 10 times in a tight loop produces byte-identical
## SVG and JSON outputs (no embedded timestamps, no nondeterministic ids,
## no font-metrics jitter).

import unittest
import isonim_tui
import std/os

const snapName = "m2_stable_across_runs"

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

proc buildAndSnap(): tuple[svg, cellmap, plaintext, ansi, treedump: string] =
  ## Build a fresh harness, mount a fixed tree, return raw encoded
  ## output for each format. We use the encoders directly to bypass
  ## the file IO and assert byte-equality across runs of the *encode*
  ## step.
  let h = newTerminalTestHarness(20, 3)
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    r.setAttribute(root, "id", "stable")
    r.appendChild(root, r.createTextNode("stable"))
    root)

  result.svg = encodeSvg(h.screenBuffer())
  result.cellmap = encodeCellMap(h.screenBuffer())
  result.plaintext = encodePlaintext(h.screenBuffer())
  result.ansi = encodeAnsi(h.screenBuffer())
  result.treedump = encodeTreeDump(h.compositor, h.root)

  h.dispose()

suite "M2: snapshot stability across runs":
  test "test_snapshot_stable_across_runs":
    cleanSnap()
    let baseline = buildAndSnap()
    for i in 1 ..< 10:
      let actual = buildAndSnap()
      check actual.svg == baseline.svg
      check actual.cellmap == baseline.cellmap
      check actual.plaintext == baseline.plaintext
      check actual.ansi == baseline.ansi
      check actual.treedump == baseline.treedump
