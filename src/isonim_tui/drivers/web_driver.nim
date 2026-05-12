## WebDriver — packet driver for serve-as-browser mode (M26).
##
## Optional driver that lets a TUI app run hosted by an out-of-process
## websocket server (`isonim-tui-serve`) which bridges packets to a
## browser-side xterm.js. The packet protocol is taken from Textual's
## `textual/drivers/web_driver.py`:
##
##   * 1-byte packet type: `D` / `M` / `P`.
##   * 4-byte big-endian length.
##   * `length` bytes of payload.
##
## Packet type semantics:
##
##   * `D` — display/output. Emitted by *the driver* to its output FD.
##     Payload is the same raw byte run a `PosixDriver` would have
##     written to stdout (cursor moves, SGR transitions, cell
##     contents). The `D` envelope is the only difference between the
##     two drivers' output bytes — concatenated `D` payloads recover
##     PosixDriver's stdout byte-stream verbatim.
##
##   * `M` — meta. Emitted *to* the driver by the host server (resize
##     announcements, ping/pong, app shutdown). Optional in the
##     reference implementation; the driver decodes well-known meta
##     names and ignores the rest.
##
##   * `P` — packetised input event. Emitted *to* the driver by the
##     host server, carrying a renderer-facing event shape. Payload is
##     a small JSON-ish encoding (single-line, ASCII-safe) — see
##     `decodeInputPacket` for the wire format.
##
## *Charter §1.* Like `PosixDriver`, `WebDriver` is a `ref object`:
## it owns OS handles, a reader thread, and an inter-thread queue.
## Every value flowing through its public API is a value type
## (`Strip`, `TerminalEvent`, `seq[byte]`).
##
## *No threading magic.* The reader uses sync `posix.read` on
## `inputFd`. The writer wraps each `flushPending()` payload in one
## `D` packet and writes it via blocking `posix.write` on `outputFd`.
## No chronos, no stdlib `asyncdispatch`. The driver is a 1:1 packet
## bridge.

import std/[locks, oserrors, posix, strutils, unicode]

import ../cells
import ../events
import ../text/ansi
import ./driver

# ---------------------------------------------------------------------------
# Wire-format helpers — packet framing
# ---------------------------------------------------------------------------
#
# All three packet types share the same framing: 1-byte type + 4-byte
# big-endian length + payload bytes. We keep the helpers isolated so
# the serve-side server (a separate repo) can re-use them via a
# shared header file or by re-implementing the same five lines.

const
  PacketTypeDisplay* = 'D'
  PacketTypeMeta* = 'M'
  PacketTypeInput* = 'P'

proc encodePacket*(kind: char; payload: string): string =
  ## Build one framed packet: 1-byte type + 4-byte big-endian length +
  ## payload. The whole result is a `string` of raw bytes (Nim strings
  ## are byte-clean).
  result = newString(5 + payload.len)
  result[0] = kind
  let n = uint32(payload.len)
  result[1] = char((n shr 24) and 0xFF)
  result[2] = char((n shr 16) and 0xFF)
  result[3] = char((n shr 8) and 0xFF)
  result[4] = char(n and 0xFF)
  if payload.len > 0:
    copyMem(addr result[5], unsafeAddr payload[0], payload.len)

type
  PacketParser* = object
    ## Streaming parser for the wire format. Feed bytes via
    ## `feedBytes`; each completed packet surfaces as `(kind,
    ## payload)` from `pop()`. Carries any partial-packet state across
    ## reads.
    buf: string
    queue: seq[tuple[kind: char; payload: string]]

proc initPacketParser*(): PacketParser =
  PacketParser(buf: "", queue: @[])

proc feedBytes*(p: var PacketParser; data: openArray[byte]) =
  if data.len > 0:
    let start = p.buf.len
    p.buf.setLen(start + data.len)
    for i in 0 ..< data.len:
      p.buf[start + i] = char(data[i])
  # Drain any complete packets out of the buffer.
  var off = 0
  while p.buf.len - off >= 5:
    let kind = p.buf[off]
    let n = (uint32(byte(p.buf[off + 1])) shl 24) or
            (uint32(byte(p.buf[off + 2])) shl 16) or
            (uint32(byte(p.buf[off + 3])) shl 8) or
            uint32(byte(p.buf[off + 4]))
    if uint32(p.buf.len - off - 5) < n:
      break
    var payload = newString(int(n))
    if n > 0'u32:
      copyMem(addr payload[0], addr p.buf[off + 5], int(n))
    p.queue.add((kind: kind, payload: payload))
    off += 5 + int(n)
  if off > 0:
    if off >= p.buf.len:
      p.buf.setLen(0)
    else:
      p.buf = p.buf[off ..^ 1]

proc feedString*(p: var PacketParser; s: string) =
  if s.len == 0: return
  var b = newSeq[byte](s.len)
  for i in 0 ..< s.len: b[i] = byte(s[i])
  p.feedBytes(b)

proc pop*(p: var PacketParser): (bool, char, string) =
  if p.queue.len == 0: return (false, '\0', "")
  let head = p.queue[0]
  p.queue.delete(0)
  return (true, head.kind, head.payload)

proc pendingPackets*(p: PacketParser): int {.inline.} = p.queue.len

# ---------------------------------------------------------------------------
# Tiny JSON-ish packet payload encode / decode
# ---------------------------------------------------------------------------
#
# Textual's `web_driver.py` exchanges JSON-encoded events. We use a
# minimal, self-contained encoder/decoder for a handful of
# renderer-facing event shapes — enough for the byte-roundtrip tests
# and the reference HTML/JS. We avoid `std/json` to keep the payload
# encoding deterministic across Nim versions and to keep this file
# dependency-free for the host server.
#
# Wire shape (single line, ASCII-safe):
#
#   key|<key-name>|<rune-or-0>|<modifiers-csv>
#   resize|<cols>|<rows>
#   mouse|<button-name>|<row>|<col>|<modifiers-csv>
#   paste|<base64-or-text>
#   quit
#
# `modifiers-csv` is a comma-separated list drawn from
# `shift,alt,ctrl,meta,hyper,super` (in that order).

proc encodeModifiers(mods: set[Modifier]): string =
  var parts: seq[string] = @[]
  if modShift in mods: parts.add "shift"
  if modAlt in mods: parts.add "alt"
  if modCtrl in mods: parts.add "ctrl"
  if modMeta in mods: parts.add "meta"
  if modHyper in mods: parts.add "hyper"
  if modSuper in mods: parts.add "super"
  parts.join(",")

proc decodeModifiers(csv: string): set[Modifier] =
  if csv.len == 0: return
  for part in csv.split(','):
    case part
    of "shift": result.incl modShift
    of "alt": result.incl modAlt
    of "ctrl": result.incl modCtrl
    of "meta": result.incl modMeta
    of "hyper": result.incl modHyper
    of "super": result.incl modSuper
    else: discard

proc mouseButtonName(b: events.MouseButton): string =
  case b
  of mbNone: "none"
  of mbLeft: "left"
  of mbMiddle: "middle"
  of mbRight: "right"
  of mbWheelUp: "wheelup"
  of mbWheelDown: "wheeldown"
  of mbWheelLeft: "wheelleft"
  of mbWheelRight: "wheelright"
  of mbBack: "back"
  of mbForward: "forward"

proc parseMouseButton(s: string): events.MouseButton =
  case s
  of "left": mbLeft
  of "middle": mbMiddle
  of "right": mbRight
  of "wheelup": mbWheelUp
  of "wheeldown": mbWheelDown
  of "wheelleft": mbWheelLeft
  of "wheelright": mbWheelRight
  of "back": mbBack
  of "forward": mbForward
  else: mbNone

proc encodeInputEvent*(ev: events.TerminalEvent): string =
  ## Encode a renderer-facing event into the `P` packet payload format.
  case ev.kind
  of ekKey:
    "key|" & ev.key.key & "|" & $ev.key.rune & "|" &
      encodeModifiers(ev.key.modifiers)
  of ekResize:
    "resize|" & $ev.resize.cols & "|" & $ev.resize.rows
  of ekMouseDown, ekMouseUp, ekMouseMove, ekScroll:
    let prefix =
      case ev.kind
      of ekMouseDown: "mousedown"
      of ekMouseUp: "mouseup"
      of ekMouseMove: "mousemove"
      of ekScroll: "scroll"
      else: "mouse"
    prefix & "|" & mouseButtonName(ev.mouse.button) & "|" &
      $ev.mouse.row & "|" & $ev.mouse.col & "|" &
      encodeModifiers(ev.mouse.modifiers)
  of ekPaste:
    "paste|" & ev.paste.text
  of ekFocus: "focus"
  of ekBlur: "blur"
  of ekCustom: "custom|" & ev.`type`

proc decodeInputPacket*(payload: string): events.TerminalEvent =
  ## Decode a `P` packet payload into a renderer-facing event. Payload
  ## shape mirrors `encodeInputEvent`. An empty / unrecognised payload
  ## becomes a custom event with type `"unknown"`.
  if payload.len == 0:
    return newCustomEvent("unknown")
  let parts = payload.split('|')
  case parts[0]
  of "key":
    if parts.len >= 4:
      let runeVal = try: parseUInt(parts[2]).uint32 except CatchableError: 0'u32
      let mods = decodeModifiers(parts[3])
      let kind = if runeVal != 0: kkChar
                 elif parts[1] in ["enter", "escape", "tab", "shift+tab",
                                   "backspace", "insert", "delete"]: kkNamed
                 elif parts[1] in ["up", "down", "left", "right",
                                   "home", "end", "pageup", "pagedown"]: kkNavigation
                 else: kkChar
      let ke = events.KeyEvent(kind: kind, key: parts[1], rune: runeVal,
                               modifiers: mods)
      result = newKeyTerminalEvent("keydown", ke)
    else:
      result = newCustomEvent("unknown")
  of "resize":
    if parts.len >= 3:
      let cols = try: parseInt(parts[1]) except CatchableError: 0
      let rows = try: parseInt(parts[2]) except CatchableError: 0
      result = TerminalEvent(kind: ekResize, `type`: "resize")
      result.resize = ResizeEvent(cols: cols, rows: rows)
    else:
      result = newCustomEvent("unknown")
  of "mousedown", "mouseup", "mousemove", "scroll":
    if parts.len >= 5:
      let button = parseMouseButton(parts[1])
      let row = try: parseInt(parts[2]) except CatchableError: 0
      let col = try: parseInt(parts[3]) except CatchableError: 0
      let mods = decodeModifiers(parts[4])
      let me = newMouseEvent(button, row, col, mods)
      let evKind =
        case parts[0]
        of "mousedown": ekMouseDown
        of "mouseup": ekMouseUp
        of "mousemove": ekMouseMove
        of "scroll": ekScroll
        else: ekMouseMove
      result = newMouseTerminalEvent(parts[0], me)
      result.kind = evKind
    else:
      result = newCustomEvent("unknown")
  of "paste":
    let txt = if parts.len >= 2: parts[1 ..^ 1].join("|") else: ""
    result = TerminalEvent(kind: ekPaste, `type`: "paste")
    result.paste = PasteEvent(text: txt)
  of "focus":
    result = TerminalEvent(kind: ekFocus, `type`: "focus")
  of "blur":
    result = TerminalEvent(kind: ekBlur, `type`: "blur")
  of "custom":
    let t = if parts.len >= 2: parts[1] else: "custom"
    result = newCustomEvent(t)
  else:
    result = newCustomEvent("unknown")

# ---------------------------------------------------------------------------
# Inter-thread event queue
# ---------------------------------------------------------------------------

type
  EventChannel = object
    chan: Channel[events.TerminalEvent]

proc initEventChannel(ch: var EventChannel) =
  open(ch.chan)

proc pushEvent(ch: var EventChannel; ev: events.TerminalEvent) =
  ch.chan.send(ev)

proc drainAll(ch: var EventChannel): seq[events.TerminalEvent] =
  result = @[]
  while true:
    let (got, ev) = ch.chan.tryRecv()
    if not got: break
    result.add ev

type
  StopFlag = object
    value: bool

  ReaderArgs = object
    inputFd: cint
    chan: ptr EventChannel
    stopRequested: ptr bool

# ---------------------------------------------------------------------------
# WebDriver
# ---------------------------------------------------------------------------

type
  WebDriver* = ref object
    ## Packet driver. Owns the stdio FDs the serve-side host process
    ## hands us, a reader thread for `P`/`M` packets, the buffered
    ## `D`-payload queue, and the inter-thread event channel.
    ##
    ## `cols`/`rows` track the latest size announced by the host (via
    ## an `M resize` packet or a `P resize` event); the compositor
    ## consults them on each frame.
    cols*: int
    rows*: int
    inputFd*: cint
    outputFd*: cint
    writeBufLock: Lock
    writeBuf: string
    currentStyle: Style
    channel: EventChannel
    stopFlag: StopFlag
    readerArgs: ReaderArgs
    readerThread: Thread[ptr ReaderArgs]
    readerSpawned: bool
    lifecycleState: DriverState
    bytesEmitted*: string    ## The concatenation of every `D` packet
                             ## payload — i.e. the byte stream a
                             ## PosixDriver would have written to
                             ## stdout for the same compositor input.
    packetsEmitted*: string  ## Mirror of every framed packet written
                             ## to `outputFd` (5-byte header + payload).
                             ## Tests assert on this for envelope-aware
                             ## checks.

  WebDriverError* = object of CatchableError

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newWebDriver*(cols, rows: int;
                   inputFd: cint = STDIN_FILENO;
                   outputFd: cint = STDOUT_FILENO): WebDriver =
  ## Allocate a new WebDriver. No OS state is touched until `start()`.
  ## `inputFd`/`outputFd` default to STDIN/STDOUT for the production
  ## case; tests pass pipe FDs to drive the same path against scripted
  ## packet sequences.
  result = WebDriver(
    cols: cols, rows: rows,
    inputFd: inputFd, outputFd: outputFd,
    writeBuf: "",
    currentStyle: defaultStyle(),
    readerSpawned: false,
    lifecycleState: dsStopped,
    bytesEmitted: "",
    packetsEmitted: "")
  initLock(result.writeBufLock)
  initEventChannel(result.channel)

# ---------------------------------------------------------------------------
# Reader-thread body
# ---------------------------------------------------------------------------

proc readerLoop(args: ptr ReaderArgs) {.thread, nimcall.} =
  var parser = initPacketParser()
  var buf: array[4096, byte]
  while not args.stopRequested[]:
    var rs: TFdSet
    FD_ZERO(rs)
    FD_SET(args.inputFd, rs)
    var tv: Timeval
    tv.tv_sec = posix.Time(0)
    tv.tv_usec = posix.Suseconds(50_000)
    let n = posix.select(args.inputFd + 1, addr rs, nil, nil, addr tv)
    if args.stopRequested[]: break
    if n <= 0:
      if n == -1:
        let e = osLastError()
        if cint(e) == EINTR: continue
      continue
    if FD_ISSET(args.inputFd, rs) == 0: continue
    let got = posix.read(args.inputFd, addr buf[0], buf.len)
    if got <= 0:
      # EOF or error — exit the reader loop. The lifecycle stop()
      # below joins us shortly.
      break
    parser.feedBytes(buf.toOpenArray(0, int(got) - 1))
    while parser.pendingPackets() > 0:
      let (ok, kind, payload) = parser.pop()
      if not ok: break
      case kind
      of PacketTypeInput:
        let ev = decodeInputPacket(payload)
        args.chan[].pushEvent(ev)
      of PacketTypeMeta:
        # Meta resize: payload encodes "resize|<cols>|<rows>".
        let parts = payload.split('|')
        if parts.len >= 3 and parts[0] == "resize":
          let cols = try: parseInt(parts[1]) except CatchableError: 0
          let rows = try: parseInt(parts[2]) except CatchableError: 0
          var ev = TerminalEvent(kind: ekResize, `type`: "resize")
          ev.resize = ResizeEvent(cols: cols, rows: rows)
          args.chan[].pushEvent(ev)
        elif parts.len >= 1 and parts[0] == "quit":
          # Server requested shutdown — surface as a synthetic ctrl+c.
          let ke = events.KeyEvent(kind: kkNamed, key: "ctrl+c",
                                   modifiers: {modCtrl})
          args.chan[].pushEvent(newKeyTerminalEvent("keydown", ke))
        # else: silently ignore unknown meta names.
      else:
        # `D` packets are server→client; receiving one server-side is
        # nonsensical. Drop.
        discard

# ---------------------------------------------------------------------------
# Start / stop
# ---------------------------------------------------------------------------

proc start*(d: WebDriver) =
  if d.lifecycleState != dsStopped:
    raise newException(WebDriverError,
      "WebDriver.start: already started (state=" &
        $d.lifecycleState & ")")
  d.lifecycleState = dsStarting
  d.stopFlag.value = false
  d.readerArgs = ReaderArgs(
    inputFd: d.inputFd,
    chan: addr d.channel,
    stopRequested: addr d.stopFlag.value)
  createThread(d.readerThread, readerLoop, addr d.readerArgs)
  d.readerSpawned = true
  d.lifecycleState = dsRunning

proc stop*(d: WebDriver) =
  if d.lifecycleState == dsStopped: return
  d.lifecycleState = dsStopping
  if d.readerSpawned:
    d.stopFlag.value = true
    joinThread(d.readerThread)
    d.readerSpawned = false
  d.lifecycleState = dsStopped

# ---------------------------------------------------------------------------
# Driver concept implementation — write / flushPending
# ---------------------------------------------------------------------------

proc writeRaw*(d: WebDriver; s: string) =
  ## Append raw ANSI bytes to the pending `D`-packet buffer.
  if s.len == 0: return
  acquire(d.writeBufLock)
  d.writeBuf.add(s)
  release(d.writeBufLock)

proc emitCellPayload(d: WebDriver; cell: Cell) =
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

proc write*(d: WebDriver; strip: Strip) =
  ## Compositor entry point. Encode every cell in the strip with
  ## minimal SGR transitions and append to the pending buffer. The
  ## strip's row position is implicit; callers wrap with
  ## `writeRaw(cursorTo(row, 0))` (mirrors PosixDriver).
  acquire(d.writeBufLock)
  for cell in strip.cells:
    d.emitCellPayload(cell)
  release(d.writeBufLock)

proc writeAt*(d: WebDriver; row: int; strip: Strip) =
  if row < 0 or row >= d.rows: return
  acquire(d.writeBufLock)
  d.writeBuf.add(cursorTo(row, 0))
  let count = min(strip.cells.len, d.cols)
  for i in 0 ..< count:
    d.emitCellPayload(strip.cells[i])
  release(d.writeBufLock)

proc writeStringAll(fd: cint; s: string) =
  ## Write all bytes of `s` to `fd`. Loops on partial writes; logs +
  ## drops on real errors (matches PosixDriver's `writeStringRaw`
  ## tolerance).
  if s.len == 0: return
  var off = 0
  while off < s.len:
    let p = cast[pointer](cast[uint](unsafeAddr s[0]) + uint(off))
    let n = posix.write(fd, p, s.len - off)
    if n <= 0:
      let e = osLastError()
      if cint(e) == EINTR: continue
      break
    off += int(n)

proc flushPending*(d: WebDriver) =
  ## Drain the pending buffer as one `D` packet. Records the payload
  ## bytes on `bytesEmitted` (so the byte-parity test can compare
  ## against PosixDriver) and the framed packet on `packetsEmitted`.
  acquire(d.writeBufLock)
  let pending = move(d.writeBuf)
  d.writeBuf = ""
  release(d.writeBufLock)
  if pending.len == 0: return
  d.bytesEmitted.add(pending)
  let packet = encodePacket(PacketTypeDisplay, pending)
  d.packetsEmitted.add(packet)
  writeStringAll(d.outputFd, packet)

proc sendMeta*(d: WebDriver; payload: string) =
  ## Emit an `M` packet to the host server. Used by app-level code to
  ## announce things like "ready", "ping", or shutdown.
  let packet = encodePacket(PacketTypeMeta, payload)
  d.packetsEmitted.add(packet)
  writeStringAll(d.outputFd, packet)

# ---------------------------------------------------------------------------
# Driver concept implementation — readEvents / resize / state / paintBuffer
# ---------------------------------------------------------------------------

proc readEvents*(d: WebDriver): seq[events.TerminalEvent] =
  result = drainAll(d.channel)

proc resize*(d: WebDriver; cols, rows: int) =
  d.cols = cols
  d.rows = rows

proc state*(d: WebDriver): DriverState {.inline.} =
  d.lifecycleState

proc paintBuffer*(d: WebDriver; buffer: ScreenBuffer) =
  ## Full-repaint helper used by the compositor's first paint. Mirrors
  ## `HeadlessDriver.paintBuffer`.
  acquire(d.writeBufLock)
  d.writeBuf.add(cursorTo(0, 0))
  let rows = min(buffer.rowsCount, d.rows)
  release(d.writeBufLock)
  for r in 0 ..< rows:
    d.writeAt(r, buffer.rows[r])

proc injectInputPacket*(d: WebDriver; payload: string) =
  ## Test-only helper: bypass the reader thread and push a decoded
  ## input event onto the channel directly. Used by the round-trip
  ## test; production code path is the reader thread reading from
  ## `inputFd`.
  let ev = decodeInputPacket(payload)
  d.channel.pushEvent(ev)

# ---------------------------------------------------------------------------
# Conformance
# ---------------------------------------------------------------------------

static:
  doAssert checkDriver(WebDriver)
