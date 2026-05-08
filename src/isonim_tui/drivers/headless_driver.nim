## HeadlessDriver — Nim port of `textual/drivers/headless_driver.py`.
##
## A driver that never touches the operating system. Tests inject
## synthetic events via `injectEvent`; the compositor pumps strips
## through `write`; the resulting `ScreenBuffer` and the byte stream
## that a real driver would have emitted are inspectable for assertions.
##
## Why a `ref object` here? The driver owns mutable buffers (event
## queue, recorded byte log, current screen contents) and is shared
## between the harness, the compositor, and the pilot. Using a `ref`
## avoids accidental copies that would defeat assertions on
## "what did this driver receive?". The data flowing through its API
## (`Strip`, `TerminalEvent`, `seq[byte]`) remains value-typed per the
## charter.

import std/[unicode]

import ../cells
import ../events
import ../text/ansi
import ./driver

type
  HeadlessDriver* = ref object
    ## A non-OS driver that records every emission and yields synthetic
    ## events on demand. Owned by `TerminalTestHarness`.
    cols*: int
    rows*: int
    buffer*: ScreenBuffer        ## What the screen would look like.
    pending*: seq[TerminalEvent] ## Synthetic events queued for the next
                                 ## `readEvents()` call.
    drainedEvents*: seq[TerminalEvent] ## Total event log across the run.
    bytesEmitted*: string        ## Byte stream a real driver would have
                                 ## written to stdout (with cursor +
                                 ## SGR + payload).
    currentStyle: Style          ## Tracks the trailing SGR style so
                                 ## successive `write` calls emit only
                                 ## minimal transitions.
    lifecycleState: DriverState

proc newHeadlessDriver*(cols, rows: int): HeadlessDriver =
  ## Construct a driver of the given dimensions. The screen buffer is
  ## allocated immediately (filled with blank cells); recorded byte
  ## stream starts empty.
  HeadlessDriver(
    cols: cols, rows: rows,
    buffer: newScreenBuffer(cols, rows),
    pending: @[], drainedEvents: @[],
    bytesEmitted: "",
    currentStyle: defaultStyle(),
    lifecycleState: dsStopped)

proc start*(d: HeadlessDriver) =
  ## Move into `dsRunning`. A real driver would call `tcsetattr` here;
  ## the headless driver just flips a flag and emits the alt-screen
  ## sequence into the byte stream so tests can assert on it.
  d.lifecycleState = dsStarting
  d.bytesEmitted.add(enableAltScreen())
  d.bytesEmitted.add(cursorHide())
  d.lifecycleState = dsRunning

proc stop*(d: HeadlessDriver) =
  ## Emit the leave-alt-screen + cursor-show sequences into the byte
  ## log and transition to `dsStopped`.
  if d.lifecycleState != dsRunning: return
  d.lifecycleState = dsStopping
  d.bytesEmitted.add(cursorShow())
  d.bytesEmitted.add(disableAltScreen())
  d.lifecycleState = dsStopped

proc state*(d: HeadlessDriver): DriverState {.inline.} =
  d.lifecycleState

proc resize*(d: HeadlessDriver; cols, rows: int) =
  ## Reallocate the screen buffer. Pre-existing content is dropped
  ## (matches what a real terminal does on a SIGWINCH-triggered redraw).
  d.cols = cols
  d.rows = rows
  d.buffer = newScreenBuffer(cols, rows)
  # Surface the resize as an event so the renderer can react.
  var ev = TerminalEvent(kind: ekResize, `type`: "resize")
  ev.resize = ResizeEvent(cols: cols, rows: rows)
  d.pending.add(ev)

proc flushPending*(d: HeadlessDriver) =
  ## A real driver would call `write(stdout, ...)` here. The headless
  ## driver has no IO; this is a no-op kept for parity. Tests may want
  ## to hook this to assert that flush was called.
  discard

proc readEvents*(d: HeadlessDriver): seq[TerminalEvent] =
  ## Drain the synthetic-event queue. Each call returns *new* events
  ## since the previous call; the full log is preserved on
  ## `drainedEvents`.
  result = d.pending
  for ev in d.pending:
    d.drainedEvents.add(ev)
  d.pending.setLen(0)

proc injectEvent*(d: HeadlessDriver; ev: TerminalEvent) =
  ## Append a synthetic event to the queue. The pilot uses this to
  ## simulate keystrokes / mouse / paste / focus-loss / resize.
  d.pending.add(ev)

proc writeRaw*(d: HeadlessDriver; s: string) =
  ## Append raw bytes to the recorded stream. The compositor uses this
  ## for cursor-move / clear / mode-set sequences.
  d.bytesEmitted.add(s)

proc emitCellPayload(d: HeadlessDriver; cell: Cell) =
  ## Encode one cell as a byte run: SGR transition + utf-8 rune. Width-0
  ## ghost cells are skipped (the trailing-half of a width-2 grapheme
  ## doesn't get its own emission).
  if cell.width == 0: return
  let target = newStyle(cell.fg, cell.bg, cell.attrs)
  let sgr = renderSgr(d.currentStyle, target)
  if sgr.len > 0:
    d.bytesEmitted.add(sgr)
    d.currentStyle = target
  if cell.rune.int32 != 0:
    d.bytesEmitted.add(toUTF8(cell.rune))
  else:
    d.bytesEmitted.add(' ')

proc write*(d: HeadlessDriver; strip: Strip) =
  ## Compositor entry point. The strip's row position is implicit —
  ## the compositor wraps each call with a `cursorTo(row, 0)` via
  ## `writeRaw`. We update the on-screen buffer row-zero by default;
  ## see `writeAt` for the addressed variant the compositor actually
  ## uses.
  for cell in strip.cells:
    d.emitCellPayload(cell)

proc writeAt*(d: HeadlessDriver; row: int; strip: Strip) =
  ## Position the cursor at (row, 0), emit SGR-aware payload for every
  ## cell in the strip, and update `d.buffer` so introspection sees the
  ## same view a real terminal would.
  if row < 0 or row >= d.rows: return
  d.bytesEmitted.add(cursorTo(row, 0))
  # Update buffer + emit bytes in a single pass.
  let count = min(strip.cells.len, d.cols)
  var newCells = newSeq[Cell](d.cols)
  for i in 0 ..< d.cols:
    if i < count:
      newCells[i] = strip.cells[i]
    else:
      newCells[i] = spaceCell()
  let newStrip = newStrip(newCells)
  d.buffer.setRow(row, newStrip)
  for cell in strip.cells[0 ..< count]:
    d.emitCellPayload(cell)

proc paintBuffer*(d: HeadlessDriver; buffer: ScreenBuffer) =
  ## Full-repaint helper. Replaces `d.buffer` and emits a positioned
  ## strip per row. The compositor calls this from M2's full-repaint
  ## path; M8 swaps it for region-targeted writes.
  d.bytesEmitted.add(cursorTo(0, 0))
  let rows = min(buffer.rowsCount, d.rows)
  for r in 0 ..< rows:
    d.writeAt(r, buffer.rows[r])

proc cellAt*(d: HeadlessDriver; row, col: int): Cell =
  ## Read one cell from the on-screen buffer. Out-of-range coordinates
  ## return `spaceCell()` so callers can do simple row/col loops without
  ## bounds-checking.
  if row < 0 or row >= d.rows: return spaceCell()
  if col < 0 or col >= d.cols: return spaceCell()
  d.buffer[row, col]

proc clearBytes*(d: HeadlessDriver) =
  ## Reset the byte log. Used by the harness between paints when the
  ## test only cares about the *next* batch of output.
  d.bytesEmitted = ""

# Compile-time conformance — same pattern as the renderer.
static:
  doAssert checkDriver(HeadlessDriver)
