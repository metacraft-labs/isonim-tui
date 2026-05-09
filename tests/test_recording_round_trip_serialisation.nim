## test_recording_round_trip_serialisation
##
## Save / reload / replay produces the same result. Forward-compat
## stays in scope: the JSON wire format keeps optional fields under
## short keys so older readers tolerate newer recordings (and
## vice-versa via tolerant parsing).

import unittest
import isonim_tui
import std/[os, tempfiles, strutils]

suite "M25: recording round-trip serialisation":
  test "test_recording_round_trip_serialisation":
    proc mountApp(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "root")
      let label = r.createTextNode("hi")
      r.appendChild(root, label)
      var counter = 0
      r.addEventListener(root, "keydown", proc() =
        inc counter
        r.setTextContent(label, "n=" & $counter))
      root

    # Record a small session.
    let rh = newRecordingHarness(30, 3)
    rh.mount(mountApp)
    rh.press("enter")
    rh.press("enter")
    rh.press("enter")
    let originalRecording = rh.recording
    let originalBuffer = rh.screenBuffer()
    rh.dispose()

    # Serialise + deserialise.
    let json = originalRecording.toJson()
    check json.len > 0
    let reloaded = fromJson(json)

    # Round-trip equivalence on the metadata.
    check reloaded.version == originalRecording.version
    check reloaded.cols == originalRecording.cols
    check reloaded.rows == originalRecording.rows
    check reloaded.events.len == originalRecording.events.len
    check reloaded.frames.len == originalRecording.frames.len

    # Per-event equivalence.
    for i, ev in originalRecording.events:
      check ev == reloaded.events[i]

    # Per-frame buffer equivalence.
    for i, frame in originalRecording.frames:
      check frame.buffer == reloaded.frames[i].buffer
      check frame.seqNumber == reloaded.frames[i].seqNumber

    # Save / load through disk produces an identical recording.
    let tmpFile = createTempFile("isonim-rec-", ".json")
    let path = tmpFile.path
    close tmpFile.cfile
    originalRecording.save(path)
    let loaded = Recording.load(path)
    check loaded.events.len == originalRecording.events.len
    check loaded.frames.len == originalRecording.frames.len
    removeFile(path)

    # Replay the reloaded recording — final buffer matches the original.
    let result = replay(reloaded, mountApp)
    check result.success
    check result.finalBuffer == originalBuffer

    # Forward-compat: a recording with extra unknown top-level fields
    # round-trips unchanged.
    let withExtras = json.replace("\"version\":", "\"futureFlag\":42,\"version\":")
    let reloadedWithExtras = fromJson(withExtras)
    check reloadedWithExtras.events.len == originalRecording.events.len
