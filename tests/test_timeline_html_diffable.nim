## test_timeline_html_diffable
##
## A recorded session produces `_timeline.html` with N frame
## thumbnails. The HTML's text content (with timestamps stripped) is
## byte-stable across runs of the same session — so it can serve as
## a golden artefact under `tests/snapshots/`.

import unittest
import isonim_tui
import std/[strutils, os]

const snapName = "m25_timeline_basic"

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

suite "M25: timeline HTML diffable":
  test "test_timeline_html_diffable":
    cleanSnap()

    proc mountApp(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.appendChild(root, r.createTextNode("ready"))
      var n = 0
      r.addEventListener(root, "keydown", proc() =
        inc n
        # Replace text child with current count.
        r.clearChildren(root)
        r.appendChild(root, r.createTextNode("n=" & $n)))
      root

    # Build a small session.
    let rh = newRecordingHarness(20, 3)
    rh.mount(mountApp)
    rh.press("enter")
    rh.press("enter")
    rh.press("enter")
    let recording = rh.recording

    # Encode the timeline twice — once with no timestamp so we can
    # compare for byte-stability.
    let html1 = encodeTimelineHtml(recording, includeTimestamp = false)
    let html2 = encodeTimelineHtml(recording, includeTimestamp = false)
    check html1 == html2
    check html1.len > 0

    # The HTML has one `<details>` block per frame (initial + 3 events).
    let detailsCount = html1.count("<details class=\"frame\"")
    check detailsCount == 4

    # The HTML mentions the session metadata.
    check html1.contains("frames: 4")
    check html1.contains("events: 3")
    check html1.contains("dimensions: 20x3")

    # Each frame has its plaintext dump embedded.
    check html1.contains("ready")
    check html1.contains("n=1")
    check html1.contains("n=3")

    # Diff blocks are present.
    check html1.contains("diff vs previous")

    # Persist via the harness's snapTimeline — first run records the
    # golden, second run compares.
    let firstResult = rh.h.snapTimeline(recording, snapName)
    check firstResult
    check fileExists(snapDir() / snapName / "_timeline.html")
    let secondResult = rh.h.snapTimeline(recording, snapName)
    check secondResult

    # The stripDynamic helper makes a real-time HTML stable.
    let liveHtml = encodeTimelineHtml(recording, includeTimestamp = true)
    let stripped1 = stripDynamic(liveHtml)
    let stripped2 = stripDynamic(liveHtml)
    check stripped1 == stripped2

    rh.dispose()
    cleanSnap()
