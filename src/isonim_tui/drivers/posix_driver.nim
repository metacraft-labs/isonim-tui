## PosixDriver — production POSIX driver (M9).
##
## The first real driver. Owns the host terminal: termios save/restore,
## alternate screen buffer, mouse mode, bracketed paste, cursor
## visibility, SIGWINCH-driven resize delivery, and signal-safe
## restoration on SIGINT/SIGTERM/SIGHUP.
##
## *Architecture.* M9 is the IsoNim-TUI-specific glue: every platform
## primitive — raw mode, alt-screen toggling, mouse-mode toggle, the
## SIGWINCH self-pipe, the byte-stream input parser — comes from the
## L3 sibling library `nim-termctl`. The driver wires those primitives
## together with:
##
##   * a *writer-thread integration* — `write(strip)` / `writeRaw(s)`
##     append to a buffered ANSI byte queue; `flushPending()` writes
##     the queued bytes to the output FD in one `write(2)` per frame;
##   * an *M4-input-parser pipeline* — a dedicated reader thread runs
##     a `select` loop on `inputFd`, feeds the read bytes into a
##     thread-local `nim_termctl.Parser`, translates each emitted
##     `Event` into the renderer-facing `events.TerminalEvent` shape
##     via `input/parser.translate`, and ships the result across to
##     the main thread through `system.Channel[T]` (which deep-copies
##     on `send` so the receiving thread sees an independently
##     allocated payload — necessary for `--mm:refc` correctness);
##   * SIGWINCH handling on the *main thread*, via `pollWinchPipe`
##     called from `readEvents`. nim-termctl stores the self-pipe FD
##     in a threadvar; consuming it on the main thread (which called
##     `installWinchHandler` from `start`) avoids the threadvar mismatch
##     that would otherwise mis-identify stdin as the winch pipe in the
##     reader thread;
##   * a *compositor handoff* — the driver implements the
##     `drivers/driver.Driver` concept (`start`/`stop`/`write`/
##     `readEvents`/`resize`/`flushPending`/`state`) so any consumer
##     written against the concept compiles unchanged across drivers.
##
## *Charter §1.* The driver is a `ref object` (it owns OS handles, a
## reader thread, and an inter-thread queue). Every value flowing
## through its public API is a value type (`Strip`, `TerminalEvent`,
## `seq[byte]`).
##
## *Signal safety.* `nim-termctl` installs SIGINT/SIGTERM/SIGHUP/SIGQUIT
## handlers on first `enableRawMode`. Those handlers run an async-
## signal-safe restoration path that uses only `tcsetattr` and
## `write(2)` — no malloc, no Nim allocation. The driver itself
## delegates entirely to those handlers; we do not install our own
## signal disposition. The destructor on the embedded `RawMode` /
## `AltScreen` / `MouseCapture` / `BracketedPaste` handles also runs
## the same restoration logic on normal scope exit (which catches
## panics: stack-unwind destructors fire before the process actually
## dies). `nim-termctl`'s atexit hook covers `quit()` and unhandled
## exception paths.

import std/[locks, options, oserrors, posix, unicode]

import nim_termctl
import nim_termctl/parser as termctlParser

import ../cells
import ../events
import ../input/parser as inputParser
import ../text/ansi
import ./driver

# ---------------------------------------------------------------------------
# Inter-thread event queue
# ---------------------------------------------------------------------------
#
# The reader thread shares decoded events with the main thread via
# Nim's built-in `Channel[T]`. We use `Channel` (rather than a plain
# `Lock` + `seq[T]` pair) because:
#
#   * Under `--mm:refc`, ref-counted objects shared across threads
#     race the per-thread heap GCs. `Channel.send` deep-copies the
#     payload, so the receiving thread sees an independently
#     allocated copy.
#   * Under arc / orc, deep-copy is still correct (slower than `move`
#     but equivalent in semantics).
#   * The `system/channels_builtin` API is stable across the charter
#     test matrix's three GCs.
#
# Channel messages: a translated `TerminalEvent` (renderer-facing
# variant), constructed in `inputParser.translate(raw)` on the reader
# thread. Each `send` deep-copies; the receiver therefore never
# accesses memory the reader thread allocated.

type
  EventChannel = object
    chan: Channel[events.TerminalEvent]

proc initEventChannel(ch: var EventChannel) =
  open(ch.chan)

proc deinitEventChannel(ch: var EventChannel) {.used.} =
  close(ch.chan)

proc pushEvent(ch: var EventChannel; ev: events.TerminalEvent) =
  ch.chan.send(ev)

proc drainAll(ch: var EventChannel): seq[events.TerminalEvent] =
  result = @[]
  while true:
    let (got, ev) = ch.chan.tryRecv()
    if not got: break
    result.add ev

# ---------------------------------------------------------------------------
# Stop flag (owned at a stable address)
# ---------------------------------------------------------------------------
#
# The reader thread observes a plain `bool` flipped by `stop()`. We
# wrap it in a tiny object so `addr d.stopFlag.value` is well-defined
# even after the driver is moved (it isn't moved, since `PosixDriver`
# is a `ref object`, but the convention is documented).

type
  StopFlag = object
    value: bool

# ---------------------------------------------------------------------------
# ReaderArgs — heap-stable bundle handed to the input thread
# ---------------------------------------------------------------------------

type
  ReaderArgs = object
    inputFd: cint
    chan: ptr EventChannel
    stopRequested: ptr bool
    enableKitty: bool

# ---------------------------------------------------------------------------
# PosixDriver
# ---------------------------------------------------------------------------

type
  PosixDriver* = ref object
    ## Production POSIX driver. Owns the input/output FDs, the
    ## nim-termctl RAII handles, the reader thread, the buffered
    ## ANSI writer, and the inter-thread event channel.
    ##
    ## Construct with `newPosixDriver(...)`. Lifecycle:
    ##
    ##   * `newPosixDriver` — allocates the driver; no OS state changed.
    ##   * `start` — claims the terminal, spawns the reader thread.
    ##   * `write` / `writeRaw` — queue bytes for the next flush.
    ##   * `flushPending` — drain the queue to the output FD.
    ##   * `readEvents` — drain decoded events from the reader thread.
    ##   * `resize` — record a new (cols, rows) — host terminal already
    ##     drove this via SIGWINCH; the driver only updates its own
    ##     dimensions for downstream consumers.
    ##   * `stop` — joins the reader thread, drops the RAII handles,
    ##     terminal returns to its pre-start state.
    cols*: int
    rows*: int
    inputFd*: cint           ## FD the reader thread polls (default STDIN)
    outputFd*: cint          ## FD `flushPending` writes to (default STDOUT)
    enableMouse*: bool       ## Whether to claim mouse mode on `start`
    enablePaste*: bool       ## Whether to claim bracketed paste on `start`
    enableAlt*: bool         ## Whether to switch to alt-screen on `start`
    rawMode: RawMode
    altScreen: AltScreen
    mouseCapture: MouseCapture
    bracketedPaste: BracketedPaste
    rawModeOwned: bool
    altScreenOwned: bool
    mouseOwned: bool
    pasteOwned: bool
    cursorHidden: bool
    writeBufLock: Lock
    writeBuf: string
    currentStyle: Style      ## Trailing SGR style across `write` calls
    channel: EventChannel
    parserUsesKitty: bool
    stopFlag: StopFlag
    readerArgs: ReaderArgs
    readerThread: Thread[ptr ReaderArgs]
    readerSpawned: bool
    lifecycleState: DriverState
    bytesEmitted*: string    ## Mirror of every byte written via
                             ## `flushPending` — tests assert on this
                             ## without having to read back from the FD.

  PosixDriverError* = object of CatchableError
    ## Raised on lifecycle misuse (start when already running, write
    ## when stopped, ...).

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newPosixDriver*(cols, rows: int;
                     inputFd: cint = STDIN_FILENO;
                     outputFd: cint = STDOUT_FILENO;
                     enableMouse: bool = true;
                     enablePaste: bool = true;
                     enableAlt: bool = true): PosixDriver =
  ## Allocate a new PosixDriver. No OS state is touched until `start()`
  ## fires. `inputFd` and `outputFd` default to STDIN/STDOUT for the
  ## production case; tests pass pty slave FDs to drive the same path
  ## against a synthetic terminal.
  result = PosixDriver(
    cols: cols,
    rows: rows,
    inputFd: inputFd,
    outputFd: outputFd,
    enableMouse: enableMouse,
    enablePaste: enablePaste,
    enableAlt: enableAlt,
    rawModeOwned: false,
    altScreenOwned: false,
    mouseOwned: false,
    pasteOwned: false,
    cursorHidden: false,
    writeBuf: "",
    currentStyle: defaultStyle(),
    parserUsesKitty: false,
    readerSpawned: false,
    lifecycleState: dsStopped,
    bytesEmitted: "")
  initLock(result.writeBufLock)
  initEventChannel(result.channel)

# ---------------------------------------------------------------------------
# Reader-thread body
# ---------------------------------------------------------------------------

proc readerLoop(args: ptr ReaderArgs) {.thread, nimcall.} =
  ## Body of the dedicated input thread.
  ##
  ## *Why we don't call `nim_termctl.pollEvent` directly.* That helper
  ## consults `winchPipeReadFd()` to multiplex stdin and the SIGWINCH
  ## self-pipe in one `select`. The pipe FDs are stored in
  ## `nim-termctl` threadvars; from this child thread the threadvar
  ## defaults to zero, which would make `select` treat fd 0 (stdin)
  ## as the winch pipe — the symptom is `ioctl(TIOCGWINSZ)` failing
  ## on every input byte. We bypass that by running our own
  ## select-and-read loop on `inputFd` only and feeding bytes into a
  ## fresh `Parser`. SIGWINCH delivery is handled separately on the
  ## main thread inside `readEvents`, which has access to the
  ## installer's threadvars.
  var parser = termctlParser.initParser()
  if args.enableKitty:
    termctlParser.enableKittyKeyboard(parser)
  var buf: array[4096, byte]
  while not args.stopRequested[]:
    # Drain any partial-sequence resolutions the parser already has.
    while termctlParser.pending(parser) > 0:
      let nxt = termctlParser.pop(parser)
      if nxt.isNone: break
      args.chan[].pushEvent(inputParser.translate(nxt.get()))

    # select(inputFd) with a short timeout so the stop flag is
    # observed within ~50ms.
    var rs: TFdSet
    FD_ZERO(rs)
    FD_SET(args.inputFd, rs)
    var tv: Timeval
    tv.tv_sec = posix.Time(0)
    tv.tv_usec = posix.Suseconds(50_000)
    let n = posix.select(args.inputFd + 1, addr rs, nil, nil, addr tv)
    if args.stopRequested[]: break
    if n == 0:
      # Timeout — give the parser a chance to age-out a bare-Escape.
      termctlParser.tick(parser)
      continue
    if n == -1:
      let e = osLastError()
      if cint(e) == EINTR: continue
      # Real error; sleep briefly to avoid a busy loop and retry.
      var ts = Timespec(tv_sec: posix.Time(0), tv_nsec: 10_000_000)
      discard nanosleep(ts, ts)
      continue
    if FD_ISSET(args.inputFd, rs) != 0:
      let got = posix.read(args.inputFd, addr buf[0], buf.len)
      if got > 0:
        termctlParser.feed(parser, buf.toOpenArray(0, int(got) - 1))
      elif got == 0:
        # EOF on input — the slave end was closed (likely by our own
        # `stop()`). Flush any remaining bare-Escape and exit.
        termctlParser.flush(parser)
        while termctlParser.pending(parser) > 0:
          let nxt = termctlParser.pop(parser)
          if nxt.isNone: break
          args.chan[].pushEvent(inputParser.translate(nxt.get()))
        break
      # else: EAGAIN/EINTR — loop and retry.

# ---------------------------------------------------------------------------
# Atexit-installed cursor-show emitter
# ---------------------------------------------------------------------------
#
# nim-termctl's `restoreTerminalSafe` already covers termios,
# alt-screen, mouse, paste, focus, and cursor — but only when
# `gNeedsRestore` is true. That flag is disarmed by `RawMode`'s
# destructor on stack unwind, so under a *normal* panic (uncaught
# exception → libc `exit` → atexit) the cursor-show in
# `restoreTerminalSafe` is skipped. We patch over that gap with an
# extra atexit hook that just emits cursor-show on the output FD we
# last started against. Async-signal-safe (uses `cWrite` only, no Nim
# allocation).

var
  gAtexitOutputFd {.threadvar.}: cint
  gAtexitCursorHidden {.threadvar.}: bool
  gAtexitInstalled {.threadvar.}: bool

proc cWrite(fd: cint; buf: pointer; count: csize_t): clong
  {.importc: "write", header: "<unistd.h>".}

proc cAtexit(fn: proc () {.cdecl.}): cint
  {.importc: "atexit", header: "<stdlib.h>".}

proc atexitShowCursor() {.cdecl.} =
  if gAtexitCursorHidden and gAtexitOutputFd >= 0:
    let s = "\x1b[?25h"
    discard cWrite(gAtexitOutputFd, cast[pointer](cstring(s)),
                   csize_t(s.len))
    gAtexitCursorHidden = false

proc installCursorShowAtexit(fd: cint) =
  ## Idempotent: registers the cursor-show atexit callback once and
  ## remembers the latest start()'s output FD.
  gAtexitOutputFd = fd
  gAtexitCursorHidden = true
  if not gAtexitInstalled:
    gAtexitInstalled = true
    discard cAtexit(atexitShowCursor)

# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------

proc enableKittyKeyboard*(d: PosixDriver) =
  ## Tell the reader thread (when it next starts) to decode
  ## `CSI ... u` as Kitty progressive-enhancement key events.
  d.parserUsesKitty = true

# ---------------------------------------------------------------------------
# Start / stop
# ---------------------------------------------------------------------------

proc start*(d: PosixDriver) =
  ## Claim the terminal. See module docstring for the step-by-step
  ## sequence; the short version is "raw mode → alt-screen → cursor
  ## hidden → mouse + paste → reader thread".
  if d.lifecycleState != dsStopped:
    raise newException(PosixDriverError,
      "PosixDriver.start: already started (state=" &
        $d.lifecycleState & ")")
  d.lifecycleState = dsStarting

  # Step 1 — SIGWINCH plumbing.
  installWinchHandler()

  # Step 2 — termios + signal handlers.
  d.rawMode = enableRawMode(d.inputFd)
  d.rawModeOwned = true

  # Step 3 — alt-screen.
  if d.enableAlt:
    d.altScreen = enterAltScreen(d.outputFd)
    d.altScreenOwned = true

  # Step 4 — cursor hidden until paint. Register an atexit hook that
  # re-emits cursor-show on a panicked exit (see the
  # `installCursorShowAtexit` block for the full rationale).
  writeStringRaw(d.outputFd, cursorHide())
  d.cursorHidden = true
  installCursorShowAtexit(d.outputFd)

  # Step 5 — mouse + paste.
  if d.enableMouse:
    d.mouseCapture = enableMouseCapture(d.outputFd)
    d.mouseOwned = true
  if d.enablePaste:
    d.bracketedPaste = enableBracketedPaste(d.outputFd)
    d.pasteOwned = true

  # Step 6 — reader thread.
  d.stopFlag.value = false
  d.readerArgs = ReaderArgs(
    inputFd: d.inputFd,
    chan: addr d.channel,
    stopRequested: addr d.stopFlag.value,
    enableKitty: d.parserUsesKitty)
  createThread(d.readerThread, readerLoop, addr d.readerArgs)
  d.readerSpawned = true

  d.lifecycleState = dsRunning

proc stop*(d: PosixDriver) =
  ## Release the terminal. Idempotent — calling `stop` twice or after a
  ## construction-only failure is safe.
  ##
  ## Order matters: the reader thread is joined *first* so it can't
  ## observe the FDs going away mid-poll; then we restore termios,
  ## leave alt-screen, drop mouse / paste, and show the cursor again.
  if d.lifecycleState == dsStopped: return
  d.lifecycleState = dsStopping

  # 1) Tell the reader thread to exit.
  if d.readerSpawned:
    d.stopFlag.value = true
    joinThread(d.readerThread)
    d.readerSpawned = false

  # 2) Drop alt-screen / mouse / paste.
  if d.pasteOwned:
    disableBracketedPaste(d.bracketedPaste)
    d.pasteOwned = false
  if d.mouseOwned:
    disableMouseCapture(d.mouseCapture)
    d.mouseOwned = false
  if d.altScreenOwned:
    leaveAltScreen(d.altScreen)
    d.altScreenOwned = false

  # 3) Show cursor + restore termios. Disarm the atexit hook too:
  # we just emitted cursor-show ourselves and don't want a second
  # one on real process exit.
  if d.cursorHidden:
    try:
      writeStringRaw(d.outputFd, cursorShow())
    except CatchableError:
      discard
    d.cursorHidden = false
  gAtexitCursorHidden = false
  if d.rawModeOwned:
    disableRawMode(d.rawMode)
    d.rawModeOwned = false

  d.lifecycleState = dsStopped

# ---------------------------------------------------------------------------
# Driver concept implementation — write / flushPending
# ---------------------------------------------------------------------------

proc writeRaw*(d: PosixDriver; s: string) =
  ## Append raw ANSI bytes to the pending write buffer. The compositor
  ## uses this for cursor-positioning, SGR transitions, screen-mode
  ## sequences, and any byte run that isn't a `Strip` payload.
  if s.len == 0: return
  acquire(d.writeBufLock)
  d.writeBuf.add(s)
  release(d.writeBufLock)

proc emitCellPayload(d: PosixDriver; cell: Cell) =
  ## SGR-aware encode of one cell into the pending buffer. Width-0
  ## ghost cells (the trailing-half of a width-2 grapheme) are
  ## skipped — the wide rune already occupied both columns.
  if cell.width == 0: return
  let target = newStyle(cell.fg, cell.bg, cell.attrs)
  let sgr = renderSgr(d.currentStyle, target)
  if sgr.len > 0:
    d.writeBuf.add(sgr)
    d.currentStyle = target
  if cell.rune.int32 != 0:
    d.writeBuf.add(toUTF8(cell.rune))
  else:
    d.writeBuf.add(' ')

proc write*(d: PosixDriver; strip: Strip) =
  ## Compositor entry point. Encode every cell in the strip as a byte
  ## run with minimal SGR transitions and append to the pending buffer.
  ## Like `HeadlessDriver.write`, the strip's row position is implicit
  ## — callers wrap each `write(strip)` with a preceding
  ## `writeRaw(cursorTo(row, 0))`.
  acquire(d.writeBufLock)
  for cell in strip.cells:
    d.emitCellPayload(cell)
  release(d.writeBufLock)

proc writeAt*(d: PosixDriver; row: int; strip: Strip) =
  ## Position the cursor at (row, 0) and emit the strip. Mirrors
  ## `HeadlessDriver.writeAt` for consumers that want a single call.
  if row < 0 or row >= d.rows: return
  acquire(d.writeBufLock)
  d.writeBuf.add(cursorTo(row, 0))
  let count = min(strip.cells.len, d.cols)
  for i in 0 ..< count:
    d.emitCellPayload(strip.cells[i])
  release(d.writeBufLock)

proc flushPending*(d: PosixDriver) =
  ## Drain the pending buffer to `outputFd` in one `write(2)` (libc
  ## may break it into multiple syscalls if the kernel buffer fills).
  ## Records the emitted bytes on `bytesEmitted` so tests can assert
  ## on the byte stream without reading back from the FD.
  acquire(d.writeBufLock)
  let pending = move(d.writeBuf)
  d.writeBuf = ""
  release(d.writeBufLock)
  if pending.len == 0: return
  d.bytesEmitted.add(pending)
  writeStringRaw(d.outputFd, pending)

# ---------------------------------------------------------------------------
# Driver concept implementation — readEvents / resize / state
# ---------------------------------------------------------------------------

proc pollWinchPipe(d: PosixDriver): seq[events.TerminalEvent] =
  ## Non-blocking check of the SIGWINCH self-pipe. Returns one
  ## `ResizeEvent` if a winch byte is pending and the host's
  ## `terminalSize()` ioctl succeeds. Idempotent — when no byte is
  ## queued, returns an empty seq.
  ##
  ## Called from the main thread. nim-termctl stores the pipe FDs as
  ## threadvars on the thread that called `installWinchHandler`; in our
  ## design that thread is whichever called `start()` (typically the
  ## main thread). The reader thread can't see the pipe at all — it
  ## only handles stdin bytes. This split avoids the threadvar
  ## mismatch that would otherwise mis-identify stdin as the winch
  ## pipe inside the reader.
  result = @[]
  let fd = winchPipeReadFd()
  if fd < 0: return
  # Non-blocking read: drain any pending bytes.
  var b: array[64, byte]
  var rs: TFdSet
  FD_ZERO(rs)
  FD_SET(fd, rs)
  var tv: Timeval
  tv.tv_sec = posix.Time(0)
  tv.tv_usec = posix.Suseconds(0)
  let n = posix.select(fd + 1, addr rs, nil, nil, addr tv)
  if n <= 0: return
  if FD_ISSET(fd, rs) == 0: return
  # Drain whatever's there.
  while true:
    let got = posix.read(fd, addr b[0], b.len)
    if got <= 0: break
  # Materialise a ResizeEvent. Prefer querying the driver's outputFd
  # directly (always a tty in our context) rather than trusting the
  # process's STDOUT to be one.
  var sizeOpt: tuple[cols, rows: int] = (cols: d.cols, rows: d.rows)
  try:
    sizeOpt = terminalSize(d.outputFd)
  except CatchableError:
    # Output FD doesn't support TIOCGWINSZ (rare; happens when a test
    # routes stdout to a pipe rather than a pty). Fall back to the
    # last-known dimensions; the application will still observe the
    # resize event but with stale numbers.
    discard
  var ev = events.TerminalEvent(kind: events.ekResize, `type`: "resize")
  ev.resize = events.ResizeEvent(cols: sizeOpt.cols, rows: sizeOpt.rows)
  result.add ev

proc readEvents*(d: PosixDriver): seq[events.TerminalEvent] =
  ## Drain every event the reader thread has queued since the last
  ## call plus any pending SIGWINCH-driven resize events. Returns an
  ## empty seq when idle. Non-blocking — callers that need to wait
  ## for an event should poll this method on a timer.
  result = drainAll(d.channel)
  let resizes = d.pollWinchPipe()
  for ev in resizes:
    result.add(ev)

proc resize*(d: PosixDriver; cols, rows: int) =
  ## Record the new terminal dimensions. The actual SIGWINCH traffic
  ## is consumed by the reader thread, which surfaces a `ResizeEvent`
  ## on the channel; the runtime loop calls this method in response to
  ## that event so the driver's idea of (cols, rows) tracks the host
  ## terminal.
  d.cols = cols
  d.rows = rows

proc state*(d: PosixDriver): DriverState {.inline.} =
  d.lifecycleState

# ---------------------------------------------------------------------------
# Conformance
# ---------------------------------------------------------------------------

static:
  doAssert checkDriver(PosixDriver)
