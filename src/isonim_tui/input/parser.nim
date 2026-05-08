## isonim_tui/input/parser.nim — terminal-byte-stream input adapter.
##
## M4 ships the *parser* in `nim-termctl/parser.nim` (the L3 sibling
## library); the heavy lifting — the 9-state FSM, bare-Escape
## disambiguation, partial-UTF-8 reassembly across reads, SGR-1006
## mouse, bracketed paste, focus events, in-band resize, Kitty
## extended-keyboard (`CSI ... u`), and reissue-on-overlength fallback —
## lives there and is exercised by `tests/test_termctl_event_decode_corpus.nim`.
##
## This module is the *renderer-side* of M4. It:
##
##   * Wraps `nim_termctl.Parser` in an `InputParser` value object
##     callers can hold without touching the lower-level type.
##   * Translates each emitted `nim_termctl.Event` into the public
##     `isonim_tui.events.TerminalEvent` shape (`Modifier` set, named
##     key strings like `"enter"`, `"ctrl+c"`, `"up"`, `"f5"`, mouse
##     button semantics matching the Pilot wiring).
##
## No `ref object`, no raw `ptr`, no mocks. Charter §1 conformance.
##
## Usage:
##
## ```nim
## import isonim_tui/input/parser
##
## var ip = initInputParser()
## ip.feed("\x1b[A")          # arrow up
## while ip.hasEvent():
##   let ev = ip.poll()
##   echo ev.key.key          # "up"
## ```

import std/[options, unicode]

import nim_termctl/parser as termctlParser
import nim_termctl/event as termctlEvent

import ../events
# Re-export so callers needing `TerminalEvent` etc. via `input/parser`
# don't have to add a separate `events` import.
export events

# ---------------------------------------------------------------------------
# Type wrapper
# ---------------------------------------------------------------------------

type
  InputParser* = object
    ## Thin value-typed wrapper around `nim_termctl.Parser`. We hold the
    ## parser inline (no `ref`) and expose a feed/poll API in
    ## isonim-tui's vocabulary. The translation from termctl's event
    ## shape to `TerminalEvent` happens at `poll()` time so callers
    ## never see termctl's types unless they peek at `p.inner`.
    inner*: termctlParser.Parser

proc initInputParser*(): InputParser =
  ## Construct a fresh, ground-state input parser.
  result.inner = termctlParser.initParser()

proc enableKittyKeyboard*(ip: var InputParser) =
  ## Enable Kitty extended-keyboard decoding (`CSI ... u`). Mirrors the
  ## upstream call; isonim-tui drivers wire this on when the active
  ## terminal advertises Kitty support.
  termctlParser.enableKittyKeyboard(ip.inner)

proc feed*(ip: var InputParser; bytes: openArray[byte]) =
  ## Feed bytes into the FSM. Zero or more events may surface; drain
  ## them with `poll()`.
  termctlParser.feed(ip.inner, bytes)

proc feed*(ip: var InputParser; s: string) =
  ## Convenience overload: feed a `string` of raw bytes.
  if s.len == 0: return
  var b = newSeq[byte](s.len)
  for i in 0 ..< s.len: b[i] = byte(s[i])
  termctlParser.feed(ip.inner, b)

proc flush*(ip: var InputParser) =
  ## Force any pending bare-Escape to surface immediately. Drivers
  ## call this on EOF; tests call this when they know no more bytes
  ## are coming.
  termctlParser.flush(ip.inner)

proc tick*(ip: var InputParser) =
  ## Resolve a pending bare-Escape if `escapeDelayMs` has elapsed.
  termctlParser.tick(ip.inner)

proc pending*(ip: InputParser): int {.inline.} =
  ## Number of decoded events still in the queue.
  termctlParser.pending(ip.inner)

# ---------------------------------------------------------------------------
# Modifier translation
# ---------------------------------------------------------------------------

proc toModifierSet(m: termctlEvent.KeyMods): set[Modifier] =
  ## Map termctl's `KeyMods` (which uses an underscore-free enum) to
  ## isonim-tui's `Modifier` set. Lock-key mods (`kmCapsLock`,
  ## `kmNumLock`) drop on the floor since the renderer-side event has
  ## no slot for them — they only exist in Kitty progressive
  ## enhancement and are reflected in `KeyEvent.state` (which we
  ## don't surface yet).
  if termctlEvent.kmShift in m: result.incl modShift
  if termctlEvent.kmCtrl in m: result.incl modCtrl
  if termctlEvent.kmAlt in m: result.incl modAlt
  if termctlEvent.kmMeta in m: result.incl modMeta
  if termctlEvent.kmSuper in m: result.incl modSuper
  if termctlEvent.kmHyper in m: result.incl modHyper

# ---------------------------------------------------------------------------
# Named-key catalogue
# ---------------------------------------------------------------------------

proc canonicalKeyName*(code: termctlEvent.KeyCode): string =
  ## Textual-style canonical key name for a non-character key. Mirrors
  ## the names `Pilot.parseKeyName` accepts so a round-trip between
  ## the byte parser and the synthetic-event path produces the same
  ## string.
  case code
  of termctlEvent.kcChar:        ""
  of termctlEvent.kcEnter:       "enter"
  of termctlEvent.kcEsc:         "escape"
  of termctlEvent.kcTab:         "tab"
  of termctlEvent.kcBackTab:     "shift+tab"
  of termctlEvent.kcBackspace:   "backspace"
  of termctlEvent.kcInsert:      "insert"
  of termctlEvent.kcDelete:      "delete"
  of termctlEvent.kcHome:        "home"
  of termctlEvent.kcEnd:         "end"
  of termctlEvent.kcPageUp:      "pageup"
  of termctlEvent.kcPageDown:    "pagedown"
  of termctlEvent.kcUp:          "up"
  of termctlEvent.kcDown:        "down"
  of termctlEvent.kcLeft:        "left"
  of termctlEvent.kcRight:       "right"
  of termctlEvent.kcF1:          "f1"
  of termctlEvent.kcF2:          "f2"
  of termctlEvent.kcF3:          "f3"
  of termctlEvent.kcF4:          "f4"
  of termctlEvent.kcF5:          "f5"
  of termctlEvent.kcF6:          "f6"
  of termctlEvent.kcF7:          "f7"
  of termctlEvent.kcF8:          "f8"
  of termctlEvent.kcF9:          "f9"
  of termctlEvent.kcF10:         "f10"
  of termctlEvent.kcF11:         "f11"
  of termctlEvent.kcF12:         "f12"
  of termctlEvent.kcUnknown:     "unknown"

proc keyKindFor(code: termctlEvent.KeyCode): KeyKind =
  case code
  of termctlEvent.kcChar:                                   kkChar
  of termctlEvent.kcEnter, termctlEvent.kcEsc,
     termctlEvent.kcTab, termctlEvent.kcBackTab,
     termctlEvent.kcBackspace, termctlEvent.kcInsert,
     termctlEvent.kcDelete:                                 kkNamed
  of termctlEvent.kcHome, termctlEvent.kcEnd,
     termctlEvent.kcPageUp, termctlEvent.kcPageDown,
     termctlEvent.kcUp, termctlEvent.kcDown,
     termctlEvent.kcLeft, termctlEvent.kcRight:             kkNavigation
  of termctlEvent.kcF1, termctlEvent.kcF2,
     termctlEvent.kcF3, termctlEvent.kcF4,
     termctlEvent.kcF5, termctlEvent.kcF6,
     termctlEvent.kcF7, termctlEvent.kcF8,
     termctlEvent.kcF9, termctlEvent.kcF10,
     termctlEvent.kcF11, termctlEvent.kcF12:                kkFunction
  of termctlEvent.kcUnknown:                                kkUnknown

proc renderKeyName(name: string; mods: set[Modifier]): string =
  ## Textual-style "ctrl+c", "shift+tab", "alt+up". Modifier order
  ## matches `Pilot.parseKeyName` for round-trip parity.
  result = ""
  if modCtrl in mods: result.add "ctrl+"
  if modAlt in mods: result.add "alt+"
  if modShift in mods and name != "tab":  # shift+tab encoded explicitly above
    result.add "shift+"
  if modMeta in mods: result.add "meta+"
  if modSuper in mods: result.add "super+"
  if modHyper in mods: result.add "hyper+"
  result.add name

# ---------------------------------------------------------------------------
# Mouse translation
# ---------------------------------------------------------------------------

proc toMouseButton(b: termctlEvent.MouseButton;
                   kind: termctlEvent.MouseKind): events.MouseButton =
  case kind
  of termctlEvent.mkScrollUp:    events.mbWheelUp
  of termctlEvent.mkScrollDown:  events.mbWheelDown
  of termctlEvent.mkScrollLeft:  events.mbWheelLeft
  of termctlEvent.mkScrollRight: events.mbWheelRight
  else:
    case b
    of termctlEvent.mbNone:   events.mbNone
    of termctlEvent.mbLeft:   events.mbLeft
    of termctlEvent.mbMiddle: events.mbMiddle
    of termctlEvent.mbRight:  events.mbRight

proc toEventKind(kind: termctlEvent.MouseKind): events.EventKind =
  case kind
  of termctlEvent.mkDown:                       events.ekMouseDown
  of termctlEvent.mkUp:                         events.ekMouseUp
  of termctlEvent.mkDrag, termctlEvent.mkMoved: events.ekMouseMove
  of termctlEvent.mkScrollUp,
     termctlEvent.mkScrollDown,
     termctlEvent.mkScrollLeft,
     termctlEvent.mkScrollRight:                events.ekScroll

# ---------------------------------------------------------------------------
# Translation core
# ---------------------------------------------------------------------------

proc translate*(src: termctlEvent.Event): events.TerminalEvent =
  ## Convert a single `nim_termctl.Event` into the public
  ## `TerminalEvent` shape. Visible for tests / direct callers.
  case src.kind
  of termctlEvent.ekKey:
    let k = src.key
    let mods = toModifierSet(k.mods)
    var keyOut: events.KeyEvent
    if k.code == termctlEvent.kcChar:
      let r = uint32(k.rune.int32)
      var name: string
      if r < 0x80'u32 and r >= 0x20'u32:
        # ASCII printable - use the character as the canonical name
        # (so `pilot.press("a")` and `parser.feed("a")` produce the
        # same `key.key`).
        name = $char(r)
      else:
        # Non-ASCII printable: use the rune itself encoded as UTF-8.
        name = $k.rune
      let displayName = renderKeyName(name, mods)
      keyOut = events.KeyEvent(kind: events.kkChar, key: displayName,
                               rune: r, modifiers: mods)
    else:
      let canonical = canonicalKeyName(k.code)
      # `kcBackTab` already encodes Shift in its canonical name
      # ("shift+tab"); strip Shift from the modifier set so we don't
      # produce "shift+shift+tab".
      var displayMods = mods
      if k.code == termctlEvent.kcBackTab:
        displayMods.excl modShift
        keyOut = events.KeyEvent(kind: keyKindFor(k.code),
                                 key: canonical, rune: 0'u32,
                                 modifiers: displayMods)
      else:
        let display = renderKeyName(canonical, displayMods)
        keyOut = events.KeyEvent(kind: keyKindFor(k.code),
                                 key: display, rune: 0'u32,
                                 modifiers: displayMods)
    let evName =
      case k.kind
      of termctlEvent.kkPress, termctlEvent.kkRepeat: "keydown"
      of termctlEvent.kkRelease: "keyup"
    result = newKeyTerminalEvent(evName, keyOut)
  of termctlEvent.ekMouse:
    let m = src.mouse
    let me = newMouseEvent(toMouseButton(m.button, m.kind),
                           m.row, m.col, toModifierSet(m.mods))
    let evKind = toEventKind(m.kind)
    let name = case evKind
               of events.ekMouseDown: "mousedown"
               of events.ekMouseUp:   "mouseup"
               of events.ekMouseMove: "mousemove"
               of events.ekScroll:    "scroll"
               else:                  "mousemove"
    result = newMouseTerminalEvent(name, me)
    result.kind = evKind
  of termctlEvent.ekResize:
    result = events.TerminalEvent(kind: events.ekResize, `type`: "resize")
    result.resize = events.ResizeEvent(cols: src.resize.cols,
                                       rows: src.resize.rows)
  of termctlEvent.ekFocus:
    result = events.TerminalEvent(
      kind: (if src.focus.gained: events.ekFocus else: events.ekBlur),
      `type`: (if src.focus.gained: "focus" else: "blur"))
  of termctlEvent.ekPaste:
    result = events.TerminalEvent(kind: events.ekPaste, `type`: "paste")
    result.paste = PasteEvent(text: src.paste)

# ---------------------------------------------------------------------------
# Drain API
# ---------------------------------------------------------------------------

proc poll*(ip: var InputParser): Option[events.TerminalEvent] =
  ## Pop the oldest queued event, translated into the public shape.
  ## Returns `none` if the queue is empty.
  let nxt = termctlParser.pop(ip.inner)
  if nxt.isNone: return none(events.TerminalEvent)
  some(translate(nxt.get()))

proc hasEvent*(ip: InputParser): bool {.inline.} =
  ip.pending() > 0

proc drain*(ip: var InputParser): seq[events.TerminalEvent] =
  ## Drain every queued event in order. Used by tests; not the
  ## production hot path (`poll()` is).
  while ip.hasEvent():
    let ev = ip.poll()
    if ev.isNone: break
    result.add ev.get()
