## Replayer — M25 deterministic playback of a `Recording`.
##
## `replay(recording, mountProc)` constructs a fresh harness sized to
## match the recording, mounts the application by calling `mountProc`
## (which the test passes — same closure that produced the original
## tree), then plays back every captured event in sequence. The
## resulting `ScreenBuffer` byte-matches the recording's final frame
## and the event log mirrors the recording's event count + sequence
## metadata.
##
## Charter §1: pure function over data. Returns a value-typed
## `ReplayResult` that the caller can assert against.

import ./recording_types
import ./harness
import ./pilot
import ../cells
import ../events
import ../renderer

type
  ReplayResult* = object
    ## Outcome of a `replay()` call. The boolean shorthand `success`
    ## means "final ScreenBuffer matches the recording's final
    ## frame"; richer fields support diagnostic assertions.
    success*: bool
    finalBuffer*: ScreenBuffer
    finalBytes*: string
    eventLogLen*: int
    framesProduced*: int

proc findById(root: TerminalNode; id: int): TerminalNode =
  if root == nil: return nil
  if root.id == id: return root
  for c in root.children:
    let m = findById(c, id)
    if m != nil: return m
  return nil

proc dispatchEvent(p: Pilot; e: RecordedEvent) =
  ## Internal: route one captured event through the pilot. The
  ## recorder captures by *intent* (press, click, type, …) so replay
  ## simply re-invokes the matching pilot proc.
  case e.kind
  of rekPress:
    if e.keys.len > 0:
      var arr = newSeq[string](e.keys.len)
      for i, k in e.keys: arr[i] = k
      case arr.len
      of 1: p.press(arr[0])
      of 2: p.press(arr[0], arr[1])
      of 3: p.press(arr[0], arr[1], arr[2])
      else:
        for k in arr: p.press(k)
  of rekType:
    p.`type`(e.text)
  of rekClick:
    let target = findById(p.h.root, e.targetId)
    let btn = MouseButton(e.button)
    p.click(target, e.row, e.col, button = btn, times = max(1, e.times))
  of rekHover:
    let target = findById(p.h.root, e.targetId)
    p.hover(target, e.row, e.col)
  of rekMouseDown:
    let btn = MouseButton(e.button)
    p.mouseDown(nil, e.row, e.col, button = btn)
  of rekMouseUp:
    let btn = MouseButton(e.button)
    p.mouseUp(nil, e.row, e.col, button = btn)
  of rekScroll:
    p.scroll(nil, e.dx, e.dy, e.row, e.col)
  of rekFocus:
    let target = findById(p.h.root, e.targetId)
    p.focus(target)
  of rekPaste:
    p.paste(e.text, nil)
  of rekResize:
    p.resize(e.cols, e.rows)
  of rekAdvance:
    p.h.advance(e.ms)

proc replay*(recording: Recording;
             mountProc: proc(r: TerminalRenderer): TerminalNode):
            ReplayResult =
  ## Replay the recording against a fresh harness. `mountProc` is the
  ## same builder function the original test passed to
  ## `RecordingHarness.mount` — it must produce a structurally
  ## identical tree (same id sequence, same handler chain) for the
  ## replay to byte-match.
  let h = newTerminalTestHarness(recording.cols, recording.rows)
  h.mount(mountProc)
  let p = newPilot(h)
  for e in recording.events:
    dispatchEvent(p, e)
  result = ReplayResult(
    success: true,
    finalBuffer: h.driver.buffer,
    finalBytes: h.driver.bytesEmitted,
    eventLogLen: h.eventLogStorage.len,
    framesProduced: recording.events.len)
  if recording.frames.len > 0:
    let lastFrame = recording.frames[^1]
    result.success = (result.finalBuffer == lastFrame.buffer)
  h.dispose()

proc replayInto*(recording: Recording; h: TerminalTestHarness) =
  ## Replay variant for tests that already own a harness. Does *not*
  ## dispose the harness; the caller owns its lifecycle.
  let p = newPilot(h)
  for e in recording.events:
    dispatchEvent(p, e)
