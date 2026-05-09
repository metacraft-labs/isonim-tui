## test_record_replay_byte_identical
##
## A 50-step session driven through the recording harness; replaying
## that recording against a fresh harness yields a byte-identical
## final ScreenBuffer and event log. Charter §1: real harness, real
## pilot, real compositor — no mocks.

import unittest
import isonim_tui
import std/unicode

suite "M25: record + replay byte-identical":
  test "test_record_replay_byte_identical":
    # Build the same app twice — once for recording, once for replay.
    proc mountApp(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "main")
      let label = r.createTextNode("0")
      r.appendChild(root, label)
      var counter = 0
      r.addEventListener(root, "keydown", proc() =
        inc counter
        r.setTextContent(label, $counter))
      root

    # === Phase 1: Record ===
    let rh = newRecordingHarness(40, 5)
    rh.mount(mountApp)
    # 50 keypresses → 50 increments.
    for i in 0 ..< 50:
      rh.press("enter")

    let originalBuffer = rh.screenBuffer()
    let originalBytes = rh.bytesEmitted()
    let originalRecording = rh.recording

    # Sanity: the recording captured 50 events + 51 frames (initial + 50).
    check originalRecording.events.len == 50
    check originalRecording.frames.len == 51
    rh.dispose()

    # === Phase 2: Replay ===
    let result = replay(originalRecording, mountApp)
    check result.success                       ## final buffer matches
    check result.finalBuffer == originalBuffer ## byte-identical screen
    # The bytes emitted should also match because driver writes are
    # deterministic when the inputs are.
    check result.finalBytes == originalBytes
    # Event log length is preserved (50 keydowns).
    check result.eventLogLen >= 50

    # The visible state shows '50'.
    let cell00 = result.finalBuffer[0, 0]
    check cell00.rune == Rune('5'.ord)
    let cell01 = result.finalBuffer[0, 1]
    check cell01.rune == Rune('0'.ord)
