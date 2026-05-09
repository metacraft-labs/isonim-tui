## Recording / Frame value types — M25.
##
## Split out from `recorder.nim` so the timeline encoder (and any
## other consumer that only reads recordings) doesn't pull in the
## full harness dependency chain. The recorder + replayer share these
## same types and own the higher-level capture / playback logic.
##
## Charter §1: every type here is a plain value object. No `ref`, no
## raw `ptr`. The `Frame` carries an embedded `ScreenBuffer` (already
## a value type) so frames are deep-copyable.

import ../cells

type
  RecordingEventKind* = enum
    ## Discriminator for `RecordedEvent`. We split the recording-time
    ## actions into a small enum of high-level operations because the
    ## raw `TerminalEvent` values aren't enough — `pilot.press("tab")`
    ## hijacks the event into a focus-manager call that never produces
    ## a `TerminalEvent`. Keeping a separate operation taxonomy here
    ## means replay reconstructs the *intent* (press, click, type,
    ## resize, paste, focus, advance) rather than just the OS-level
    ## event stream.
    rekPress       ## A pilot.press(keys) call
    rekType        ## A pilot.`type`(text) call
    rekClick       ## A pilot.click(...) call
    rekHover       ## A pilot.hover(...) call
    rekMouseDown
    rekMouseUp
    rekScroll
    rekFocus       ## A pilot.focus(node) call
    rekPaste       ## A pilot.paste(text)
    rekResize      ## A pilot.resize(cols, rows)
    rekAdvance     ## h.advance(ms)

  RecordedEvent* = object
    seqNumber*: int
    kind*: RecordingEventKind
    keys*: seq[string]
    text*: string
    targetId*: int
    row*: int
    col*: int
    dx*: int
    dy*: int
    button*: int
    times*: int
    cols*: int
    rows*: int
    ms*: int

  Frame* = object
    seqNumber*: int
    buffer*: ScreenBuffer
    bytesEmitted*: string
    eventLogLen*: int

  Recording* = object
    version*: int
    cols*: int
    rows*: int
    events*: seq[RecordedEvent]
    frames*: seq[Frame]

const recordingVersion* = 1

proc frames*(r: Recording): seq[Frame] = r.frames
proc events*(r: Recording): seq[RecordedEvent] = r.events

proc `==`*(a, b: RecordedEvent): bool =
  a.seqNumber == b.seqNumber and a.kind == b.kind and
    a.keys == b.keys and a.text == b.text and
    a.targetId == b.targetId and a.row == b.row and
    a.col == b.col and a.dx == b.dx and a.dy == b.dy and
    a.button == b.button and a.times == b.times and
    a.cols == b.cols and a.rows == b.rows and a.ms == b.ms
