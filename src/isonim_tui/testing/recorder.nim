## Recorder — M25 deterministic event-recording harness.
##
## The `RecordingHarness` wraps a `TerminalTestHarness` and captures
## *every* input event, signal-write boundary, and frame commit into a
## serialisable `Recording`. Replaying that recording against a fresh
## harness produces a byte-identical `ScreenBuffer` and event log — a
## power tool for bug-report reproducibility and time-travel
## debugging.
##
## Charter §1: the recording itself is a value type composed of value
## types (defined in `recording_types.nim`). `RecordingHarness` is
## `ref object` because it holds the harness pointer plus mutable
## buffers; the `Recording` it produces is fully copyable.
##
## Wire format: a single JSON object with `version`, `cols`, `rows`,
## an array of `events`, and an array of `frames`. Forward / backward
## compat is provided by the `version` field plus tolerant parsing —
## unknown event kinds are skipped on replay so older recordings load
## against newer codebases.

import std/[json, unicode]

import ../cells
import ../events
import ../renderer
import ./harness
import ./pilot
import ./recording_types

export recording_types

type
  RecordingHarness* = ref object
    ## A thin recording shim. Owns a real harness + a real pilot;
    ## every input action invoked through this object is captured into
    ## the recording before being forwarded to the underlying pilot.
    ## After each captured event we snapshot the screen + bytes into
    ## a new Frame.
    h*: TerminalTestHarness
    pilot*: Pilot
    recording*: Recording

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newRecordingHarness*(width, height: int): RecordingHarness =
  ## Construct a fresh recording harness. Internally creates a real
  ## `TerminalTestHarness` and a pilot bound to it.
  let h = newTerminalTestHarness(width, height)
  RecordingHarness(
    h: h,
    pilot: newPilot(h),
    recording: Recording(
      version: recordingVersion, cols: width, rows: height,
      events: @[], frames: @[]))

proc dispose*(rh: RecordingHarness) =
  if rh.h != nil:
    rh.h.dispose()

# ----------------------------------------------------------------------------
# Frame capture
# ----------------------------------------------------------------------------

proc snapshotFrame(rh: RecordingHarness; seqNumber: int) =
  let buf = rh.h.driver.buffer
  let bytes = rh.h.driver.bytesEmitted
  rh.recording.frames.add Frame(
    seqNumber: seqNumber,
    buffer: buf,
    bytesEmitted: bytes,
    eventLogLen: rh.h.eventLogStorage.len)

proc nextSeq(rh: RecordingHarness): int =
  rh.recording.events.len + 1

# ----------------------------------------------------------------------------
# Captured input actions — recorder-flavoured wrappers around pilot procs.
# ----------------------------------------------------------------------------

proc press*(rh: RecordingHarness; keys: varargs[string]) =
  let s = nextSeq(rh)
  var keyList: seq[string] = @[]
  for k in keys: keyList.add k
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekPress, keys: keyList)
  rh.pilot.press(keys)
  snapshotFrame(rh, s)

proc `type`*(rh: RecordingHarness; text: string) =
  let s = nextSeq(rh)
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekType, text: text)
  rh.pilot.`type`(text)
  snapshotFrame(rh, s)

proc typeText*(rh: RecordingHarness; text: string) {.inline.} =
  `type`(rh, text)

proc click*(rh: RecordingHarness; target: TerminalNode = nil;
            row: int = 0; col: int = 0;
            button: MouseButton = mbLeft; times: int = 1) =
  let s = nextSeq(rh)
  let id = if target != nil: target.id else: 0
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekClick,
    targetId: id, row: row, col: col, button: ord(button), times: times)
  rh.pilot.click(target, row, col, button = button, times = times)
  snapshotFrame(rh, s)

proc hover*(rh: RecordingHarness; target: TerminalNode = nil;
            row: int = 0; col: int = 0) =
  let s = nextSeq(rh)
  let id = if target != nil: target.id else: 0
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekHover, targetId: id, row: row, col: col)
  rh.pilot.hover(target, row, col)
  snapshotFrame(rh, s)

proc paste*(rh: RecordingHarness; text: string;
            target: TerminalNode = nil) =
  let s = nextSeq(rh)
  let id = if target != nil: target.id else: 0
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekPaste, text: text, targetId: id)
  rh.pilot.paste(text, target)
  snapshotFrame(rh, s)

proc resize*(rh: RecordingHarness; cols, rows: int) =
  let s = nextSeq(rh)
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekResize, cols: cols, rows: rows)
  rh.pilot.resize(cols, rows)
  snapshotFrame(rh, s)

proc advance*(rh: RecordingHarness; ms: int) =
  let s = nextSeq(rh)
  rh.recording.events.add RecordedEvent(
    seqNumber: s, kind: rekAdvance, ms: ms)
  rh.h.advance(ms)
  snapshotFrame(rh, s)

# ----------------------------------------------------------------------------
# Mount + tree access (pass-through to the underlying harness)
# ----------------------------------------------------------------------------

proc mount*(rh: RecordingHarness;
            buildProc: proc(r: TerminalRenderer): TerminalNode) =
  rh.h.mount(buildProc)
  # Capture an initial frame at sequence 0 so the timeline always has
  # a starting state to diff against.
  rh.recording.frames.add Frame(
    seqNumber: 0,
    buffer: rh.h.driver.buffer,
    bytesEmitted: rh.h.driver.bytesEmitted,
    eventLogLen: rh.h.eventLogStorage.len)

proc screenBuffer*(rh: RecordingHarness): ScreenBuffer =
  rh.h.driver.buffer

proc bytesEmitted*(rh: RecordingHarness): string =
  rh.h.driver.bytesEmitted

# ----------------------------------------------------------------------------
# Cell / Strip / ScreenBuffer JSON encoding for the wire format.
# ----------------------------------------------------------------------------

proc colorToJson(c: Color): JsonNode =
  result = newJObject()
  result["k"] = %ord(c.kind).int
  case c.kind
  of ckDefault: discard
  of ckAnsi: result["a"] = %ord(c.ansi).int
  of ckIndexed: result["i"] = %c.indexed.int
  of ckRgb:
    result["r"] = %c.r.int
    result["g"] = %c.g.int
    result["b"] = %c.b.int

proc colorFromJson(j: JsonNode): Color =
  if j == nil or j.kind != JObject: return defaultColor()
  let k = ColorKind(j["k"].getInt)
  case k
  of ckDefault: defaultColor()
  of ckAnsi: ansiColor(AnsiColor(j["a"].getInt))
  of ckIndexed: indexedColor(j["i"].getInt.uint8)
  of ckRgb:
    rgbColor(j["r"].getInt.uint8, j["g"].getInt.uint8, j["b"].getInt.uint8)

proc attrsToJson(s: set[Attr]): JsonNode =
  result = newJArray()
  for a in s:
    result.add %ord(a).int

proc attrsFromJson(j: JsonNode): set[Attr] =
  result = {}
  if j == nil or j.kind != JArray: return
  for el in j.elems:
    result.incl Attr(el.getInt)

proc cellToJson(c: Cell): JsonNode =
  result = newJObject()
  result["u"] = %c.rune.int32.int
  result["fg"] = colorToJson(c.fg)
  result["bg"] = colorToJson(c.bg)
  result["a"] = attrsToJson(c.attrs)
  result["w"] = %c.width.int

proc cellFromJson(j: JsonNode): Cell =
  result = spaceCell()
  if j == nil or j.kind != JObject: return
  result.rune = Rune(j["u"].getInt)
  result.fg = colorFromJson(j["fg"])
  result.bg = colorFromJson(j["bg"])
  result.attrs = attrsFromJson(j["a"])
  result.width = j["w"].getInt.int8

proc bufferToJson(b: ScreenBuffer): JsonNode =
  result = newJObject()
  result["cols"] = %b.cols
  result["rows"] = %b.rowsCount
  let rowsArr = newJArray()
  for r in 0 ..< b.rowsCount:
    let row = newJArray()
    for c in 0 ..< b.cols:
      row.add cellToJson(b.rows[r].cells[c])
    rowsArr.add row
  result["data"] = rowsArr

proc bufferFromJson(j: JsonNode): ScreenBuffer =
  let cols = j["cols"].getInt
  let rows = j["rows"].getInt
  result = newScreenBuffer(cols, rows)
  let arr = j["data"]
  for r in 0 ..< rows:
    var cells = newSeq[Cell](cols)
    let rowArr = arr[r]
    for c in 0 ..< cols:
      cells[c] = cellFromJson(rowArr[c])
    result.setRow(r, newStrip(cells))

proc eventToJson(e: RecordedEvent): JsonNode =
  result = newJObject()
  result["seq"] = %e.seqNumber
  result["kind"] = %ord(e.kind).int
  if e.keys.len > 0:
    let arr = newJArray()
    for k in e.keys: arr.add %k
    result["keys"] = arr
  if e.text.len > 0: result["text"] = %e.text
  if e.targetId != 0: result["tgt"] = %e.targetId
  if e.row != 0: result["row"] = %e.row
  if e.col != 0: result["col"] = %e.col
  if e.dx != 0: result["dx"] = %e.dx
  if e.dy != 0: result["dy"] = %e.dy
  if e.button != 0: result["btn"] = %e.button
  if e.times != 0: result["times"] = %e.times
  if e.cols != 0: result["cols"] = %e.cols
  if e.rows != 0: result["rows"] = %e.rows
  if e.ms != 0: result["ms"] = %e.ms

proc eventFromJson(j: JsonNode): RecordedEvent =
  result = RecordedEvent()
  result.seqNumber = j["seq"].getInt
  result.kind = RecordingEventKind(j["kind"].getInt)
  if j.hasKey("keys"):
    for k in j["keys"].elems:
      result.keys.add k.getStr
  if j.hasKey("text"): result.text = j["text"].getStr
  if j.hasKey("tgt"): result.targetId = j["tgt"].getInt
  if j.hasKey("row"): result.row = j["row"].getInt
  if j.hasKey("col"): result.col = j["col"].getInt
  if j.hasKey("dx"): result.dx = j["dx"].getInt
  if j.hasKey("dy"): result.dy = j["dy"].getInt
  if j.hasKey("btn"): result.button = j["btn"].getInt
  if j.hasKey("times"): result.times = j["times"].getInt
  if j.hasKey("cols"): result.cols = j["cols"].getInt
  if j.hasKey("rows"): result.rows = j["rows"].getInt
  if j.hasKey("ms"): result.ms = j["ms"].getInt

proc frameToJson(f: Frame): JsonNode =
  result = newJObject()
  result["seq"] = %f.seqNumber
  result["buf"] = bufferToJson(f.buffer)
  result["bytes"] = %f.bytesEmitted
  result["log"] = %f.eventLogLen

proc frameFromJson(j: JsonNode): Frame =
  Frame(
    seqNumber: j["seq"].getInt,
    buffer: bufferFromJson(j["buf"]),
    bytesEmitted: j["bytes"].getStr,
    eventLogLen: j["log"].getInt)

# ----------------------------------------------------------------------------
# Public serialisation API
# ----------------------------------------------------------------------------

proc toJson*(r: Recording): string =
  ## Serialise the recording to a JSON string suitable for writing to
  ## disk. The body is a single JObject so order is stable across
  ## runs.
  var root = newJObject()
  root["version"] = %r.version
  root["cols"] = %r.cols
  root["rows"] = %r.rows
  let evArr = newJArray()
  for e in r.events: evArr.add eventToJson(e)
  root["events"] = evArr
  let frArr = newJArray()
  for f in r.frames: frArr.add frameToJson(f)
  root["frames"] = frArr
  $root

proc fromJson*(s: string): Recording =
  ## Reverse of `toJson`. Tolerant: missing optional fields default to
  ## the zero value, unknown fields are ignored. Unknown event kinds
  ## are skipped on replay so a forward-incompatible recording loads
  ## without crashing.
  let root = parseJson(s)
  result = Recording(version: 0, cols: 0, rows: 0, events: @[], frames: @[])
  if root.hasKey("version"): result.version = root["version"].getInt
  if root.hasKey("cols"): result.cols = root["cols"].getInt
  if root.hasKey("rows"): result.rows = root["rows"].getInt
  if root.hasKey("events"):
    for j in root["events"].elems:
      try:
        result.events.add eventFromJson(j)
      except CatchableError:
        discard
  if root.hasKey("frames"):
    for j in root["frames"].elems:
      try:
        result.frames.add frameFromJson(j)
      except CatchableError:
        discard

proc save*(r: Recording; path: string) =
  ## Write a recording to disk. Mirrors `toJson` + `writeFile`.
  writeFile(path, r.toJson() & "\n")

proc load*(_: typedesc[Recording]; path: string): Recording =
  ## Load a recording from disk. Counterpart of `save`.
  fromJson(readFile(path))
