## WindowsDriver — production Windows driver (M10).
##
## Win32 Console API counterpart to `PosixDriver`. Same Driver concept,
## same renderer-facing event surface (`KeyEvent`, `MouseEvent`,
## `ResizeEvent`), but built on `ReadConsoleInputW` structured records
## and `ENABLE_VIRTUAL_TERMINAL_PROCESSING` for output.
##
## *Architecture.* M10 wires the IsoNim-TUI-specific glue around the
## Windows backend exposed by `nim-termctl` (raw mode, alt-screen,
## mouse capture, bracketed paste, console-mode save/restore, terminal
## size). The driver adds:
##
##   * a *writer-thread integration* — `write(strip)` / `writeRaw(s)`
##     append SGR-aware byte runs to a buffered ANSI queue;
##     `flushPending()` drains the queue to stdout in one write per
##     frame. Modern Windows Terminal speaks the full VT escape suite
##     once we set `ENABLE_VIRTUAL_TERMINAL_PROCESSING`; legacy
##     `cmd.exe` still gets the bytes through `WriteConsoleW`'s VT
##     translator;
##   * a *structured-record input loop* — a dedicated reader thread
##     calls `ReadConsoleInputW` against the input handle, decodes
##     `KEY_EVENT_RECORD` / `MOUSE_EVENT_RECORD` /
##     `WINDOW_BUFFER_SIZE_RECORD` into renderer-facing
##     `events.TerminalEvent` shapes, and ships them across via
##     `system.Channel[T]` (deep-copy on `send`, like PosixDriver, so
##     refc / arc / orc all see independently allocated payloads);
##   * *capability detection* — when `ENABLE_VIRTUAL_TERMINAL_INPUT`
##     can't be set (Windows < 10 1809 or a non-VT host), the
##     structured-record path still emits the same typed events. We
##     never try the byte-stream parser on Windows: the console API
##     hands us decoded records directly;
##   * *console-mode save/restore* — saved on `start()`, restored on
##     `stop()` and in a `SetConsoleCtrlHandler` callback that
##     intercepts Ctrl+C / Ctrl+Break and the close / logoff /
##     shutdown notifications;
##   * *clean Ctrl+C handling* — a `SetConsoleCtrlHandler` registers
##     a routine that emits the leave sequences and signals the
##     reader thread to stop before the OS terminates the process.
##
## *Charter §1.* The driver itself is a `ref object` (it owns Win32
## handles, a reader thread, an inter-thread channel). Every value
## flowing through its public API is a value type (`Strip`,
## `TerminalEvent`, `seq[byte]`).
##
## *Compile-time guards.* This file imports `nim_termctl`'s Windows
## backend, which itself is `when defined(windows)` only. To keep the
## file *compileable on Linux* (so the rest of the build doesn't
## branch on host OS), every reference into the Win32 API and the
## Windows backend is gated on `when defined(windows)`. On non-Windows
## hosts the module exposes the public type and proc signatures as
## stubs that raise `WindowsDriverError("not supported on this host")`.
## Tests that exercise the driver use `when not defined(windows): skip()`.

import std/[locks, unicode]

import ../cells
import ../events
import ../text/ansi
import ./driver

when defined(windows):
  import nim_termctl

# ---------------------------------------------------------------------------
# Win32 FFI subset — only what the driver itself needs.
# ---------------------------------------------------------------------------
#
# nim_termctl's `windows_backend` already wraps GetStdHandle /
# GetConsoleMode / SetConsoleMode and the RAII handles. The driver
# reaches *past* that for input decoding (the backend documents
# ReadConsoleInputW as deferred) — so we declare the FFI here.

when defined(windows):
  type
    HANDLE* = pointer
    DWORD* = uint32
    BOOL* = int32
    WORD* = uint16
    SHORT* = int16
    WCHAR* = uint16

    CoordRec {.importc: "COORD", header: "<windows.h>", pure, final.} = object
      x: SHORT
      y: SHORT

    KeyEventRec {.importc: "KEY_EVENT_RECORD",
                  header: "<windows.h>", pure, final.} = object
      bKeyDown: BOOL
      wRepeatCount: WORD
      wVirtualKeyCode: WORD
      wVirtualScanCode: WORD
      uChar: WCHAR             ## Union member: UnicodeChar (we always read
                               ## the UTF-16 code unit; the AsciiChar variant
                               ## is for legacy callers).
      dwControlKeyState: DWORD

    MouseEventRec {.importc: "MOUSE_EVENT_RECORD",
                    header: "<windows.h>", pure, final.} = object
      dwMousePosition: CoordRec
      dwButtonState: DWORD
      dwControlKeyState: DWORD
      dwEventFlags: DWORD

    WindowBufferSizeRec {.importc: "WINDOW_BUFFER_SIZE_RECORD",
                           header: "<windows.h>", pure, final.} = object
      dwSize: CoordRec

    InputRecord {.importc: "INPUT_RECORD",
                   header: "<windows.h>", pure, final.} = object
      eventType: WORD
      ## The actual union of the five Event sub-records. We pick the
      ## widest (KEY_EVENT_RECORD is the largest at 16 bytes on x64,
      ## MOUSE is 16 too) and reinterpret via `cast`. Since this is
      ## inside a `when defined(windows)` block targeting a real Win32
      ## build, sizeof is determined by the actual `<windows.h>`.
      ## We use a fixed buffer matching `INPUT_RECORD`'s tail size:
      ## 16 bytes covers all variants on both x86 and x64.
      eventBlob: array[16, byte]

    PHandlerRoutine = proc (ctrlType: DWORD): BOOL {.stdcall.}

  const
    KEY_EVENT_KIND       = WORD(0x0001)
    MOUSE_EVENT_KIND     = WORD(0x0002)
    WINDOW_BUFFER_SIZE_KIND = WORD(0x0004)
    MENU_EVENT_KIND      = WORD(0x0008)
    FOCUS_EVENT_KIND     = WORD(0x0010)

    # Control-key-state flags from <windows.h>. We OR the LEFT_*/RIGHT_*
    # variants because terminals generally don't distinguish.
    RIGHT_ALT_PRESSED    = DWORD(0x0001)
    LEFT_ALT_PRESSED     = DWORD(0x0002)
    RIGHT_CTRL_PRESSED   = DWORD(0x0004)
    LEFT_CTRL_PRESSED    = DWORD(0x0008)
    SHIFT_PRESSED        = DWORD(0x0010)
    # Lock keys (NUMLOCK_ON, SCROLLLOCK_ON, CAPSLOCK_ON, ENHANCED_KEY)
    # are intentionally not decoded — the renderer-side `Modifier` enum
    # has no slot for them and Textual matches.

    # Mouse event flags.
    MOUSE_MOVED          = DWORD(0x0001)
    MOUSE_WHEELED        = DWORD(0x0004)
    MOUSE_HWHEELED       = DWORD(0x0008)
    # DOUBLE_CLICK (0x0002) is left out — we surface a normal mousedown
    # and let consumers detect double-click on their own timer.

    # Mouse button-state masks.
    FROM_LEFT_1ST_BUTTON_PRESSED = DWORD(0x0001)
    RIGHTMOST_BUTTON_PRESSED     = DWORD(0x0002)
    FROM_LEFT_2ND_BUTTON_PRESSED = DWORD(0x0004)
    FROM_LEFT_3RD_BUTTON_PRESSED = DWORD(0x0008)
    FROM_LEFT_4TH_BUTTON_PRESSED = DWORD(0x0010)

    # SetConsoleCtrlHandler control-type values.
    CTRL_C_EVENT         = DWORD(0)
    CTRL_BREAK_EVENT     = DWORD(1)
    CTRL_CLOSE_EVENT     = DWORD(2)
    CTRL_LOGOFF_EVENT    = DWORD(5)
    CTRL_SHUTDOWN_EVENT  = DWORD(6)

    # Virtual-key codes used by the named-key map.
    VK_BACK     = WORD(0x08)
    VK_TAB      = WORD(0x09)
    VK_RETURN   = WORD(0x0D)
    VK_ESCAPE   = WORD(0x1B)
    VK_SPACE    = WORD(0x20)
    VK_PRIOR    = WORD(0x21)
    VK_NEXT     = WORD(0x22)
    VK_END      = WORD(0x23)
    VK_HOME     = WORD(0x24)
    VK_LEFT     = WORD(0x25)
    VK_UP       = WORD(0x26)
    VK_RIGHT    = WORD(0x27)
    VK_DOWN     = WORD(0x28)
    VK_INSERT   = WORD(0x2D)
    VK_DELETE   = WORD(0x2E)
    VK_F1       = WORD(0x70)
    # VK_F2..VK_F24 are sequential from VK_F1.

    STD_INPUT_HANDLE_VAL  = DWORD(-10'i32)
    STD_OUTPUT_HANDLE_VAL = DWORD(-11'i32)

  proc winGetStdHandle(nStdHandle: DWORD): HANDLE
    {.importc: "GetStdHandle", header: "<windows.h>", stdcall.}

  proc readConsoleInputW(hConsole: HANDLE; lpBuffer: ptr InputRecord;
                         nLength: DWORD; lpNumberOfEventsRead: ptr DWORD): BOOL
    {.importc: "ReadConsoleInputW", header: "<windows.h>", stdcall.}

  proc waitForSingleObject(hHandle: HANDLE; dwMilliseconds: DWORD): DWORD
    {.importc: "WaitForSingleObject", header: "<windows.h>", stdcall.}

  proc setConsoleCtrlHandler(handler: PHandlerRoutine; add: BOOL): BOOL
    {.importc: "SetConsoleCtrlHandler", header: "<windows.h>", stdcall.}

  proc writeConsoleW(hConsole: HANDLE; lpBuffer: pointer;
                     nNumberOfCharsToWrite: DWORD;
                     lpNumberOfCharsWritten: ptr DWORD;
                     lpReserved: pointer): BOOL
    {.importc: "WriteConsoleW", header: "<windows.h>", stdcall.}

  const
    WAIT_OBJECT_0 = DWORD(0)
    WAIT_TIMEOUT  = DWORD(0x0102)

# ---------------------------------------------------------------------------
# Inter-thread event queue (mirrors PosixDriver).
# ---------------------------------------------------------------------------

type
  EventChannel = object
    chan: Channel[events.TerminalEvent]

proc initEventChannel(ch: var EventChannel) =
  open(ch.chan)

proc deinitEventChannel(ch: var EventChannel) {.used.} =
  close(ch.chan)

proc pushEvent(ch: var EventChannel; ev: events.TerminalEvent) {.used.} =
  ch.chan.send(ev)

proc drainAll(ch: var EventChannel): seq[events.TerminalEvent] =
  result = @[]
  while true:
    let (got, ev) = ch.chan.tryRecv()
    if not got: break
    result.add ev

# ---------------------------------------------------------------------------
# Stop flag (heap-stable address).
# ---------------------------------------------------------------------------

type
  StopFlag = object
    value: bool

# ---------------------------------------------------------------------------
# Reader-thread argument bundle.
# ---------------------------------------------------------------------------

when defined(windows):
  type
    ReaderArgs = object
      inputHandle: HANDLE
      chan: ptr EventChannel
      stopRequested: ptr bool
else:
  type
    ReaderArgs = object
      ## On non-Windows the reader thread never starts; the type still
      ## has to exist so `Thread[ptr ReaderArgs]` is declarable and the
      ## driver compiles.
      chan: ptr EventChannel
      stopRequested: ptr bool

# ---------------------------------------------------------------------------
# WindowsDriver
# ---------------------------------------------------------------------------

type
  WindowsDriver* = ref object
    ## Production Windows driver. Mirrors `PosixDriver`'s public surface
    ## but consumes the Win32 Console API. Construct with
    ## `newWindowsDriver(...)`.
    ##
    ## Lifecycle:
    ##   * `newWindowsDriver` — allocates; no console state changed.
    ##   * `start` — saves console modes, sets VT processing, switches
    ##     to alt-screen, hides the cursor, registers the
    ##     SetConsoleCtrlHandler routine, spawns the reader thread.
    ##   * `write` / `writeRaw` — queue bytes for the next flush.
    ##   * `flushPending` — drain the queue to stdout.
    ##   * `readEvents` — drain decoded events from the reader thread.
    ##   * `resize` — record a new (cols, rows). The actual change is
    ##     surfaced via `WINDOW_BUFFER_SIZE_RECORD`s on the input
    ##     handle; the runtime loop calls this proc in response.
    ##   * `stop` — joins the reader thread, restores console modes,
    ##     leaves alt-screen, disarms the Ctrl handler.
    cols*: int
    rows*: int
    enableMouse*: bool
    enablePaste*: bool
    enableAlt*: bool
    when defined(windows):
      rawMode: RawMode
      altScreen: AltScreen
      mouseCapture: MouseCapture
      bracketedPaste: BracketedPaste
      inputHandle: HANDLE
      outputHandle: HANDLE
      ctrlHandlerInstalled: bool
    rawModeOwned: bool
    altScreenOwned: bool
    mouseOwned: bool
    pasteOwned: bool
    cursorHidden: bool
    writeBufLock: Lock
    writeBuf: string
    currentStyle: Style
    channel: EventChannel
    stopFlag: StopFlag
    readerArgs: ReaderArgs
    readerThread: Thread[ptr ReaderArgs]
    readerSpawned: bool
    lifecycleState: DriverState
    bytesEmitted*: string

  WindowsDriverError* = object of CatchableError
    ## Raised on lifecycle misuse (start when already running, write
    ## when stopped, ...) and on non-Windows hosts when any proc that
    ## needs the Win32 API is invoked.

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newWindowsDriver*(cols, rows: int;
                       enableMouse: bool = true;
                       enablePaste: bool = true;
                       enableAlt: bool = true): WindowsDriver =
  ## Allocate a new WindowsDriver. No console state is touched until
  ## `start()` fires. Unlike PosixDriver this proc takes no FDs — Win32
  ## addresses the console by `GetStdHandle(STD_INPUT_HANDLE)` /
  ## `STD_OUTPUT_HANDLE`, which is what every Win32 console call
  ## resolves to anyway.
  result = WindowsDriver(
    cols: cols,
    rows: rows,
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
    readerSpawned: false,
    lifecycleState: dsStopped,
    bytesEmitted: "")
  initLock(result.writeBufLock)
  initEventChannel(result.channel)

# ---------------------------------------------------------------------------
# Modifier and key-name decoding (Win32 → renderer-side)
# ---------------------------------------------------------------------------

when defined(windows):
  proc decodeModifiers(controlKeyState: DWORD): set[events.Modifier] =
    ## Map Win32 control-key-state bits to the renderer-side `Modifier`
    ## set. Lock keys (caps/num/scroll) drop on the floor — there's no
    ## `Modifier` slot for them; mirroring Textual.
    if (controlKeyState and SHIFT_PRESSED) != 0:
      result.incl events.modShift
    if (controlKeyState and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) != 0:
      result.incl events.modCtrl
    if (controlKeyState and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) != 0:
      result.incl events.modAlt

  proc namedKeyFor(vk: WORD): string =
    ## Map Win32 virtual-key codes to canonical Textual-style key names.
    ## Returns "" for keys that should be reported via their character
    ## payload (printable runes).
    case vk
    of VK_BACK:   "backspace"
    of VK_TAB:    "tab"
    of VK_RETURN: "enter"
    of VK_ESCAPE: "escape"
    of VK_SPACE:  "space"
    of VK_PRIOR:  "pageup"
    of VK_NEXT:   "pagedown"
    of VK_END:    "end"
    of VK_HOME:   "home"
    of VK_LEFT:   "left"
    of VK_UP:     "up"
    of VK_RIGHT:  "right"
    of VK_DOWN:   "down"
    of VK_INSERT: "insert"
    of VK_DELETE: "delete"
    else:
      if vk >= VK_F1 and vk < VK_F1 + WORD(24):
        "f" & $(int(vk) - int(VK_F1) + 1)
      else:
        ""

  proc kindForName(name: string): events.KeyKind =
    ## Pick the right `KeyKind` for a named key (matches the POSIX path
    ## via `keymap.kindForName`). The naive switch covers the named
    ## keys we emit; everything else is `kkChar`.
    if name.len == 0: events.kkUnknown
    elif name.len >= 2 and name[0] == 'f' and
         (let c = name[1]; c >= '0' and c <= '9'):
      events.kkFunction
    elif name in ["up", "down", "left", "right",
                  "home", "end", "pageup", "pagedown"]:
      events.kkNavigation
    else:
      events.kkNamed

  proc translateKeyRecord(rec: KeyEventRec): events.TerminalEvent =
    ## Build a `TerminalEvent(kind: ekKey)` from a `KEY_EVENT_RECORD`.
    ## Only key-down records emit events (key-up records are swallowed
    ## to mirror POSIX behaviour, where we only see press semantics
    ## from the byte-stream parser; the Pilot harness shape doesn't
    ## carry release events either).
    var key: events.KeyEvent
    key.modifiers = decodeModifiers(rec.dwControlKeyState)
    let named = namedKeyFor(rec.wVirtualKeyCode)
    if named.len > 0:
      key.kind = kindForName(named)
      key.key = named
      key.rune = 0'u32
    elif rec.uChar != 0:
      let cp = uint32(rec.uChar)
      key.kind = events.kkChar
      key.rune = cp
      # Canonical Textual-style name: lowercase ASCII letter, or the
      # rune itself UTF-8-encoded for printables.
      var s = ""
      try:
        s.add toUTF8(Rune(int32(cp)))
      except CatchableError:
        s = ""
      key.key = s
    else:
      key.kind = events.kkUnknown
      key.key = ""
      key.rune = 0'u32
    result = events.newKeyTerminalEvent("keydown", key)

  proc translateMouseRecord(rec: MouseEventRec): events.TerminalEvent =
    ## Build a `TerminalEvent(kind: ekMouseDown/Up/Move/Scroll)` from a
    ## `MOUSE_EVENT_RECORD`. We pick the discriminator from the event
    ## flags + button-state delta. Wheel deltas come through as
    ## scroll events with `mbWheelUp` / `mbWheelDown`.
    var ev: events.TerminalEvent
    ev.targetId = 0
    ev.currentTargetId = 0
    var mouse: events.MouseEvent
    mouse.col = int(rec.dwMousePosition.x)
    mouse.row = int(rec.dwMousePosition.y)
    mouse.modifiers = decodeModifiers(rec.dwControlKeyState)

    if (rec.dwEventFlags and MOUSE_WHEELED) != 0:
      # High word of dwButtonState is signed wheel delta.
      let high = int16(int32(rec.dwButtonState) shr 16)
      mouse.button =
        if high > 0: events.mbWheelUp
        else: events.mbWheelDown
      ev.kind = events.ekScroll
      ev.`type` = "scroll"
    elif (rec.dwEventFlags and MOUSE_HWHEELED) != 0:
      let high = int16(int32(rec.dwButtonState) shr 16)
      mouse.button =
        if high > 0: events.mbWheelRight
        else: events.mbWheelLeft
      ev.kind = events.ekScroll
      ev.`type` = "scroll"
    elif (rec.dwEventFlags and MOUSE_MOVED) != 0:
      mouse.button =
        if (rec.dwButtonState and FROM_LEFT_1ST_BUTTON_PRESSED) != 0:
          events.mbLeft
        elif (rec.dwButtonState and RIGHTMOST_BUTTON_PRESSED) != 0:
          events.mbRight
        elif (rec.dwButtonState and FROM_LEFT_2ND_BUTTON_PRESSED) != 0:
          events.mbMiddle
        else:
          events.mbNone
      ev.kind = events.ekMouseMove
      ev.`type` = "mousemove"
    else:
      # Press / release. We don't have prior-state to infer release
      # cleanly; treat any non-zero button state as a press, all-zero
      # as a release.
      let pressed = rec.dwButtonState != 0
      mouse.button =
        if (rec.dwButtonState and FROM_LEFT_1ST_BUTTON_PRESSED) != 0:
          events.mbLeft
        elif (rec.dwButtonState and RIGHTMOST_BUTTON_PRESSED) != 0:
          events.mbRight
        elif (rec.dwButtonState and FROM_LEFT_2ND_BUTTON_PRESSED) != 0:
          events.mbMiddle
        elif (rec.dwButtonState and FROM_LEFT_3RD_BUTTON_PRESSED) != 0:
          events.mbBack
        elif (rec.dwButtonState and FROM_LEFT_4TH_BUTTON_PRESSED) != 0:
          events.mbForward
        else:
          events.mbNone
      if pressed:
        ev.kind = events.ekMouseDown
        ev.`type` = "mousedown"
      else:
        ev.kind = events.ekMouseUp
        ev.`type` = "mouseup"
    ev.mouse = mouse
    result = ev

  proc translateResizeRecord(rec: WindowBufferSizeRec):
                              events.TerminalEvent =
    ## Build a `ResizeEvent` from a WINDOW_BUFFER_SIZE_RECORD.
    var ev = events.TerminalEvent(kind: events.ekResize, `type`: "resize")
    ev.resize = events.ResizeEvent(cols: int(rec.dwSize.x),
                                   rows: int(rec.dwSize.y))
    result = ev

# ---------------------------------------------------------------------------
# Reader-thread body (Windows only)
# ---------------------------------------------------------------------------

when defined(windows):
  proc readerLoop(args: ptr ReaderArgs) {.thread, nimcall.} =
    ## Body of the dedicated input thread.
    ##
    ## Calls `WaitForSingleObject(inputHandle, 50ms)` so the stop flag is
    ## observed within ~50 ms of `stop()` flipping it. When the wait
    ## returns `WAIT_OBJECT_0` we drain pending records via
    ## `ReadConsoleInputW(buf, 64)` and translate each.
    ##
    ## *Why we don't use overlapped I/O.* Console handles aren't
    ## overlapped-capable in the documented Win32 surface. The
    ## "wait + read non-blocking" pattern is the standard idiom and
    ## what Microsoft's own samples use.
    var buf: array[64, InputRecord]
    while not args.stopRequested[]:
      let waitResult = waitForSingleObject(args.inputHandle, DWORD(50))
      if args.stopRequested[]: break
      if waitResult == WAIT_TIMEOUT: continue
      if waitResult != WAIT_OBJECT_0:
        # Handle error or abandoned — bail.
        break
      var nread: DWORD = 0
      let ok = readConsoleInputW(args.inputHandle, addr buf[0],
                                  DWORD(buf.len), addr nread)
      if ok == 0:
        # ReadConsoleInputW failed; sleep briefly and retry.
        let _ = waitForSingleObject(args.inputHandle, DWORD(10))
        continue
      for i in 0 ..< int(nread):
        let recPtr = addr buf[i]
        case recPtr.eventType
        of KEY_EVENT_KIND:
          # Reinterpret the union member. The actual KEY_EVENT_RECORD is
          # in the eventBlob; cast through pointer arithmetic.
          let kePtr = cast[ptr KeyEventRec](addr recPtr.eventBlob[0])
          if kePtr.bKeyDown != 0:
            args.chan[].pushEvent(translateKeyRecord(kePtr[]))
        of MOUSE_EVENT_KIND:
          let mePtr = cast[ptr MouseEventRec](addr recPtr.eventBlob[0])
          args.chan[].pushEvent(translateMouseRecord(mePtr[]))
        of WINDOW_BUFFER_SIZE_KIND:
          let wePtr = cast[ptr WindowBufferSizeRec](addr recPtr.eventBlob[0])
          args.chan[].pushEvent(translateResizeRecord(wePtr[]))
        of MENU_EVENT_KIND, FOCUS_EVENT_KIND:
          # Menu and focus records aren't surfaced through the renderer
          # event taxonomy (focus uses its own ekFocus/ekBlur path that
          # the M9 PosixDriver also doesn't emit yet). Drop them.
          discard
        else:
          discard

# ---------------------------------------------------------------------------
# Ctrl handler (Windows only)
# ---------------------------------------------------------------------------
#
# `SetConsoleCtrlHandler` registers a callback called on Ctrl+C /
# Ctrl+Break / window-close / logoff / shutdown. The handler runs on a
# dedicated OS-spawned thread, so we keep the body minimal: signal the
# reader thread to stop and emit the leave sequences directly through
# the saved output handle. Returning `TRUE` tells Windows we handled
# the event; for Ctrl+C this prevents the default (terminate process)
# and lets the reader thread drain cleanly.

when defined(windows):
  var
    gCtrlHandlerOutputHandle {.threadvar.}: HANDLE
    gCtrlHandlerStopFlag {.threadvar.}: ptr bool
    gCtrlHandlerInstalled {.threadvar.}: bool

  proc emitLeaveSequencesViaConsole(h: HANDLE) =
    ## Async-signal-equivalent: emit the leave sequences directly via
    ## `WriteConsoleW`. We can't allocate Nim memory safely on a Win32
    ## handler thread, so we use a fixed UTF-16 literal on the stack.
    if h == nil: return
    # ESC[?1049l ESC[?25h ESC[?1006l ESC[?1000l ESC[?2004l
    var seq: array[24, WCHAR] = [
      WCHAR(0x1B), WCHAR(ord('[')), WCHAR(ord('?')), WCHAR(ord('1')),
      WCHAR(ord('0')), WCHAR(ord('4')), WCHAR(ord('9')), WCHAR(ord('l')),
      WCHAR(0x1B), WCHAR(ord('[')), WCHAR(ord('?')), WCHAR(ord('2')),
      WCHAR(ord('5')), WCHAR(ord('h')),
      WCHAR(0x1B), WCHAR(ord('[')), WCHAR(ord('?')), WCHAR(ord('1')),
      WCHAR(ord('0')), WCHAR(ord('0')), WCHAR(ord('0')), WCHAR(ord('l')),
      WCHAR(0x0D), WCHAR(0x0A)
    ]
    var written: DWORD = 0
    discard writeConsoleW(h, addr seq[0], DWORD(seq.len), addr written, nil)

  proc ctrlHandlerRoutine(ctrlType: DWORD): BOOL {.stdcall.} =
    ## Win32 console control handler. Tells the reader thread to stop
    ## and emits the leave sequences. Returns TRUE for the events we
    ## want to claim (CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT)
    ## and FALSE otherwise so the default handler chains.
    case ctrlType
    of CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT,
       CTRL_LOGOFF_EVENT, CTRL_SHUTDOWN_EVENT:
      if gCtrlHandlerStopFlag != nil:
        gCtrlHandlerStopFlag[] = true
      emitLeaveSequencesViaConsole(gCtrlHandlerOutputHandle)
      return BOOL(1)
    else:
      return BOOL(0)

  proc installCtrlHandler(d: WindowsDriver) =
    ## Idempotent: registers the SetConsoleCtrlHandler callback once and
    ## remembers the latest start()'s output handle + stop flag. Called
    ## from `start()` after the rest of the lifecycle is in place.
    gCtrlHandlerOutputHandle = d.outputHandle
    gCtrlHandlerStopFlag = addr d.stopFlag.value
    if not gCtrlHandlerInstalled:
      gCtrlHandlerInstalled =
        setConsoleCtrlHandler(ctrlHandlerRoutine, BOOL(1)) != 0

  proc uninstallCtrlHandler() =
    ## Reverse of installCtrlHandler; called from `stop()` so a later
    ## process-wide Ctrl+C doesn't trigger a handler that points at a
    ## now-stopped driver.
    if gCtrlHandlerInstalled:
      discard setConsoleCtrlHandler(ctrlHandlerRoutine, BOOL(0))
      gCtrlHandlerInstalled = false
    gCtrlHandlerStopFlag = nil
    gCtrlHandlerOutputHandle = nil

# ---------------------------------------------------------------------------
# Start / stop
# ---------------------------------------------------------------------------

proc start*(d: WindowsDriver) =
  ## Claim the console. The sequence mirrors PosixDriver: raw mode +
  ## VT processing → alt-screen → cursor hidden → mouse + paste →
  ## reader thread + Ctrl handler.
  if d.lifecycleState != dsStopped:
    raise newException(WindowsDriverError,
      "WindowsDriver.start: already started (state=" &
        $d.lifecycleState & ")")
  d.lifecycleState = dsStarting

  when defined(windows):
    # Step 1 — capture stdin/stdout handles. Win32 console procs
    # take an explicit HANDLE; we resolve them once on start.
    d.inputHandle = winGetStdHandle(STD_INPUT_HANDLE_VAL)
    d.outputHandle = winGetStdHandle(STD_OUTPUT_HANDLE_VAL)

    # Step 2 — termctl raw mode. Saves current console modes and sets
    # ENABLE_VIRTUAL_TERMINAL_INPUT on stdin and
    # ENABLE_VIRTUAL_TERMINAL_PROCESSING on stdout.
    d.rawMode = enableRawMode()
    d.rawModeOwned = true

    # Step 3 — alt-screen. Modern Windows Terminal honours
    # `\x1b[?1049h` once VT processing is on.
    if d.enableAlt:
      d.altScreen = enterAltScreen()
      d.altScreenOwned = true

    # Step 4 — cursor hidden until paint.
    write(cursorHide())
    d.cursorHidden = true

    # Step 5 — mouse + paste.
    if d.enableMouse:
      d.mouseCapture = enableMouseCapture()
      d.mouseOwned = true
    if d.enablePaste:
      d.bracketedPaste = enableBracketedPaste()
      d.pasteOwned = true

    # Step 6 — reader thread. ReaderArgs lives on the driver so
    # `addr` is heap-stable for the whole lifetime.
    d.stopFlag.value = false
    d.readerArgs = ReaderArgs(
      inputHandle: d.inputHandle,
      chan: addr d.channel,
      stopRequested: addr d.stopFlag.value)
    createThread(d.readerThread, readerLoop, addr d.readerArgs)
    d.readerSpawned = true

    # Step 7 — SetConsoleCtrlHandler.
    installCtrlHandler(d)
    d.ctrlHandlerInstalled = true

    d.lifecycleState = dsRunning
  else:
    # Non-Windows hosts can't run this driver; tests must skip.
    raise newException(WindowsDriverError,
      "WindowsDriver requires a Windows host")

proc stop*(d: WindowsDriver) =
  ## Release the console. Idempotent.
  ##
  ## Order matters: the reader thread is joined first so it can't
  ## observe the input handle going away mid-read; then mouse / paste
  ## / alt-screen / cursor / raw mode unwind in reverse construction
  ## order via their RAII destructors (we still call the explicit
  ## `disable*` helpers so behaviour is observable in tests that
  ## introspect byte streams before scope unwind).
  if d.lifecycleState == dsStopped: return
  d.lifecycleState = dsStopping

  when defined(windows):
    # 1) Tell the reader thread to exit.
    if d.readerSpawned:
      d.stopFlag.value = true
      joinThread(d.readerThread)
      d.readerSpawned = false

    # 2) Drop the Ctrl handler.
    if d.ctrlHandlerInstalled:
      uninstallCtrlHandler()
      d.ctrlHandlerInstalled = false

    # 3) Drop alt-screen / mouse / paste.
    if d.pasteOwned:
      disableBracketedPaste(d.bracketedPaste)
      d.pasteOwned = false
    if d.mouseOwned:
      disableMouseCapture(d.mouseCapture)
      d.mouseOwned = false
    if d.altScreenOwned:
      leaveAltScreen(d.altScreen)
      d.altScreenOwned = false

    # 4) Show cursor + restore console modes.
    if d.cursorHidden:
      try:
        write(cursorShow())
      except CatchableError:
        discard
      d.cursorHidden = false
    if d.rawModeOwned:
      disableRawMode(d.rawMode)
      d.rawModeOwned = false

  d.lifecycleState = dsStopped

# ---------------------------------------------------------------------------
# Driver concept implementation — write / flushPending
# ---------------------------------------------------------------------------

proc writeRaw*(d: WindowsDriver; s: string) =
  ## Append raw ANSI bytes to the pending write buffer.
  if s.len == 0: return
  acquire(d.writeBufLock)
  d.writeBuf.add(s)
  release(d.writeBufLock)

proc emitCellPayload(d: WindowsDriver; cell: Cell) =
  ## SGR-aware encode of one cell into the pending buffer.
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

proc write*(d: WindowsDriver; strip: Strip) =
  ## Compositor entry point. Mirrors PosixDriver.write.
  acquire(d.writeBufLock)
  for cell in strip.cells:
    d.emitCellPayload(cell)
  release(d.writeBufLock)

proc writeAt*(d: WindowsDriver; row: int; strip: Strip) =
  ## Position the cursor at (row, 0) and emit the strip.
  if row < 0 or row >= d.rows: return
  acquire(d.writeBufLock)
  d.writeBuf.add(cursorTo(row, 0))
  let count = min(strip.cells.len, d.cols)
  for i in 0 ..< count:
    d.emitCellPayload(strip.cells[i])
  release(d.writeBufLock)

proc flushPending*(d: WindowsDriver) =
  ## Drain the pending buffer to stdout in one shot. Records the
  ## emitted bytes on `bytesEmitted` so tests can assert on the byte
  ## stream without reading back from the console.
  acquire(d.writeBufLock)
  let pending = move(d.writeBuf)
  d.writeBuf = ""
  release(d.writeBufLock)
  if pending.len == 0: return
  d.bytesEmitted.add(pending)
  when defined(windows):
    # nim-termctl's writeStringRaw on Windows routes through stdout +
    # flushFile. WriteConsoleW would be more correct for UTF-16
    # console hosts, but with VT processing on the byte stream is
    # what every modern Windows shell ingests.
    writeStringRaw(cint(1), pending)
  else:
    # Non-Windows: bytesEmitted still tracks the run for tests that
    # assert on it via the harness. No actual IO.
    discard

# ---------------------------------------------------------------------------
# Driver concept implementation — readEvents / resize / state
# ---------------------------------------------------------------------------

proc readEvents*(d: WindowsDriver): seq[events.TerminalEvent] =
  ## Drain every event the reader thread has queued since the last
  ## call. Returns an empty seq when idle. Non-blocking — callers that
  ## need to wait should poll on a timer.
  result = drainAll(d.channel)

proc resize*(d: WindowsDriver; cols, rows: int) =
  ## Record the new console dimensions. The actual size change comes
  ## through the `WINDOW_BUFFER_SIZE_RECORD` path; the runtime loop
  ## calls this proc in response so the driver's idea of (cols, rows)
  ## tracks the host.
  d.cols = cols
  d.rows = rows

proc state*(d: WindowsDriver): DriverState {.inline.} =
  d.lifecycleState

# ---------------------------------------------------------------------------
# Conformance
# ---------------------------------------------------------------------------

static:
  doAssert checkDriver(WindowsDriver)
