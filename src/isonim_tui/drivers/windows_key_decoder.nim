## windows_key_decoder — turn Win32 `KEY_EVENT_RECORD`s into `KeyEvent`s.
##
## The Windows driver's reader thread reads `INPUT_RECORD`s with
## `ReadConsoleInputW`. This module holds the key-record half of the
## decoding, as pure Nim over plain integers, so it compiles and is
## tested on every host. `windows_driver` copies each native record into
## a `WinKeyRecord` and hands it here.
##
## *Two shapes of key record.* The driver enables
## `ENABLE_VIRTUAL_TERMINAL_INPUT` (through `nim_termctl.enableRawMode`).
## Microsoft documents that flag as: "Setting this flag directs the
## Virtual Terminal processing engine to convert user input received by
## the console window into Console Virtual Terminal Sequences that can be
## retrieved by a supporting application through ReadFile or
## ReadConsole functions"
## (https://learn.microsoft.com/en-us/windows/console/setconsolemode;
## the sequences are listed under "Input Sequences" in
## https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences).
## What reaches `ReadConsoleInputW` in that mode is shown by conhost's
## input buffer (microsoft/terminal `src/host/inputBuffer.cpp`,
## `InputBuffer::_WriteBuffer` and `InputBuffer::_writeString`, read at
## 92f2a771057116d4313a5f1ef7801d9e04902a85):
##
## * a key the VT module translates is replaced by one record per UTF-16
##   code unit of the VT text, each built as
##   `SynthesizeKeyEvent(true, 1, 0, 0, wch, 0)` — key down, virtual key
##   0, scan code 0, no control-key state. Ctrl+C becomes one record
##   carrying `0x03` and nothing else; Up becomes `ESC [ A` as three
##   records;
## * a key the VT module leaves alone keeps its original record, with its
##   virtual key and control-key state.
##
## Which keys a given conhost translates varies by Windows build: on the
## CI host Enter and 'a' kept their records while Ctrl+C was replaced.
## So the decoder accepts both shapes in any interleaving. A
## *VT-translated* record (virtual key 0, scan code 0, a character) is a
## byte of the VT input stream, decoded by the same `nim_termctl` byte
## parser the POSIX driver runs, so C0 controls, CSI/SS3 keys, SGR mouse
## reports and bracketed paste mean what they mean on POSIX. Any other
## record is decoded structurally from its virtual key and control-key
## state, as before.
##
## *Naming.* Key events from both paths use this driver's convention: the
## bare key name in `key` ("c", "up", "enter") and the modifiers in
## `modifiers`. The byte parser's `translate` renders "ctrl+c" instead,
## so key events from the VT path are renamed here; mouse and paste
## events pass through unchanged.

import std/[monotimes, options, unicode]

# The byte-parser modules define their own `Event`/`KeyEvent`/`ekKey`;
# import them qualified-only so the renderer-side names stay unambiguous.
from nim_termctl/event as termctlEvent import nil
from nim_termctl/parser as termctlParser import nil

import ../events
from ../input/parser as inputParser import nil

type
  WinKeyRecord* = object
    ## The fields of a Win32 `KEY_EVENT_RECORD`
    ## (https://learn.microsoft.com/en-us/windows/console/key-event-record-str)
    ## that the decoder reads, as plain integers.
    keyDown*: bool                ## `bKeyDown != 0`
    virtualKeyCode*: uint16       ## `wVirtualKeyCode`
    virtualScanCode*: uint16      ## `wVirtualScanCode`
    unicodeChar*: uint16          ## `uChar.UnicodeChar` (one UTF-16 unit)
    controlKeyState*: uint32      ## `dwControlKeyState`

  WinKeyDecoder* = object
    ## Decoder state carried across records: the VT byte parser (an
    ## escape sequence spans several records) and a pending UTF-16 high
    ## surrogate.
    parser: termctlParser.Parser
    highSurrogate: uint16

const
  # Control-key-state flags from <wincon.h>
  # (https://learn.microsoft.com/en-us/windows/console/key-event-record-str).
  RightAltPressed* = 0x0001'u32
  LeftAltPressed* = 0x0002'u32
  RightCtrlPressed* = 0x0004'u32
  LeftCtrlPressed* = 0x0008'u32
  ShiftPressed* = 0x0010'u32

  # Virtual-key codes from <winuser.h>
  # (https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes).
  VkBack* = 0x08'u16
  VkTab* = 0x09'u16
  VkReturn* = 0x0D'u16
  VkEscape* = 0x1B'u16
  VkSpace* = 0x20'u16
  VkPrior* = 0x21'u16
  VkNext* = 0x22'u16
  VkEnd* = 0x23'u16
  VkHome* = 0x24'u16
  VkLeft* = 0x25'u16
  VkUp* = 0x26'u16
  VkRight* = 0x27'u16
  VkDown* = 0x28'u16
  VkInsert* = 0x2D'u16
  VkDelete* = 0x2E'u16
  VkF1* = 0x70'u16
  # VK_F2..VK_F24 follow VK_F1.

proc initWinKeyDecoder*(): WinKeyDecoder =
  WinKeyDecoder(parser: termctlParser.initParser(), highSurrogate: 0)

proc decodeModifiers*(controlKeyState: uint32): set[Modifier] =
  ## Map Win32 control-key-state bits to the renderer-side `Modifier`
  ## set. Lock keys (caps/num/scroll) drop on the floor — there's no
  ## `Modifier` slot for them; mirroring Textual.
  if (controlKeyState and ShiftPressed) != 0:
    result.incl modShift
  if (controlKeyState and (LeftCtrlPressed or RightCtrlPressed)) != 0:
    result.incl modCtrl
  if (controlKeyState and (LeftAltPressed or RightAltPressed)) != 0:
    result.incl modAlt

proc namedKeyFor(vk: uint16): string =
  ## Map Win32 virtual-key codes to canonical Textual-style key names.
  ## Returns "" for keys that should be reported via their character
  ## payload (printable runes).
  case vk
  of VkBack: "backspace"
  of VkTab: "tab"
  of VkReturn: "enter"
  of VkEscape: "escape"
  of VkSpace: "space"
  of VkPrior: "pageup"
  of VkNext: "pagedown"
  of VkEnd: "end"
  of VkHome: "home"
  of VkLeft: "left"
  of VkUp: "up"
  of VkRight: "right"
  of VkDown: "down"
  of VkInsert: "insert"
  of VkDelete: "delete"
  else:
    if vk >= VkF1 and vk < VkF1 + 24'u16:
      "f" & $(int(vk) - int(VkF1) + 1)
    else:
      ""

proc kindForName(name: string): KeyKind =
  ## Pick the right `KeyKind` for a named key (matches the POSIX path
  ## via `keymap.kindForName`). The naive switch covers the named
  ## keys we emit; everything else is `kkChar`.
  if name.len == 0: kkUnknown
  elif name.len >= 2 and name[0] == 'f' and
       (let c = name[1]; c >= '0' and c <= '9'):
    kkFunction
  elif name in ["up", "down", "left", "right",
                "home", "end", "pageup", "pagedown"]:
    kkNavigation
  else:
    kkNamed

proc runeKeyName(cp: uint32): string =
  ## Canonical name of a character key: the character itself, UTF-8
  ## encoded ("a", "é"). An unencodable code point yields "".
  try:
    result = toUTF8(Rune(int32(cp)))
  except CatchableError:
    result = ""

proc isVtTranslated*(rec: WinKeyRecord): bool =
  ## True for a record conhost synthesized from VT input text: virtual
  ## key 0, scan code 0, and a character (see the module comment). Such a
  ## record carries one UTF-16 unit of the VT input stream, and its zero
  ## control-key state says nothing about the modifiers held.
  rec.keyDown and rec.virtualKeyCode == 0 and rec.virtualScanCode == 0 and
    rec.unicodeChar != 0

proc translateStructured(rec: WinKeyRecord): TerminalEvent =
  ## Build a key event from a record that kept its virtual key.
  var key: KeyEvent
  key.modifiers = decodeModifiers(rec.controlKeyState)
  let named = namedKeyFor(rec.virtualKeyCode)
  if named.len > 0:
    key.kind = kindForName(named)
    key.key = named
    key.rune = 0'u32
  elif rec.unicodeChar in 1'u16 .. 26'u16:
    # A C0 control from a letter key. Only Ctrl produces one (Tab, Enter,
    # Backspace and Escape have their own virtual keys and were named
    # above), so report the letter with Ctrl, as the POSIX byte parser
    # does for the same byte — even when the record's control-key state
    # does not carry the Ctrl bit.
    let letter = uint32(ord('a')) + uint32(rec.unicodeChar) - 1
    key.kind = kkChar
    key.rune = letter
    key.key = $char(letter)
    key.modifiers.incl modCtrl
  elif rec.unicodeChar != 0:
    let cp = uint32(rec.unicodeChar)
    key.kind = kkChar
    key.rune = cp
    key.key = runeKeyName(cp)
  else:
    key.kind = kkUnknown
    key.key = ""
    key.rune = 0'u32
  result = newKeyTerminalEvent("keydown", key)

proc fromByteParser(src: termctlEvent.Event): TerminalEvent =
  ## Translate a byte-parser event with the POSIX translator, then give
  ## key events this driver's naming (bare key name, modifiers apart).
  result = inputParser.translate(src)
  if src.kind != termctlEvent.ekKey:
    return
  let k = src.key
  var mods = result.key.modifiers
  var name: string
  var kind: KeyKind
  case k.code
  of termctlEvent.kcChar:
    let cp = uint32(k.rune.int32)
    if cp == 0x20'u32:
      # The structured path names the space bar; keep one spelling.
      name = "space"
      kind = kkNamed
    else:
      name = runeKeyName(cp)
      kind = kkChar
  of termctlEvent.kcBackTab:
    # The translator spells this "shift+tab" and drops Shift from the set.
    name = "tab"
    kind = kkNamed
    mods.incl modShift
  else:
    name = inputParser.canonicalKeyName(k.code)
    kind = kindForName(name)
  result.key.key = name
  result.key.kind = kind
  result.key.modifiers = mods

proc drainParser(d: var WinKeyDecoder; sink: var seq[TerminalEvent]) =
  while termctlParser.pending(d.parser) > 0:
    let nxt = termctlParser.pop(d.parser)
    if nxt.isNone: break
    sink.add fromByteParser(nxt.get())

proc feedUnit(d: var WinKeyDecoder; unit: uint16) =
  ## Feed one UTF-16 unit of the VT stream to the byte parser as UTF-8.
  var cp: int32
  if unit >= 0xD800'u16 and unit <= 0xDBFF'u16:
    # High surrogate: conhost writes a pair as two records
    # (`_writeString` emits one record per `wchar_t`). Wait for the low.
    d.highSurrogate = unit
    return
  elif unit >= 0xDC00'u16 and unit <= 0xDFFF'u16:
    if d.highSurrogate == 0:
      return  # an unpaired low surrogate encodes nothing; drop it
    cp = 0x10000'i32 + ((int32(d.highSurrogate) - 0xD800'i32) shl 10) +
      (int32(unit) - 0xDC00'i32)
  else:
    cp = int32(unit)
  d.highSurrogate = 0
  let utf8 = toUTF8(Rune(cp))
  var bytes = newSeq[byte](utf8.len)
  for i, c in utf8:
    bytes[i] = byte(c)
  termctlParser.feed(d.parser, bytes)

proc flush*(d: var WinKeyDecoder; sink: var seq[TerminalEvent]) =
  ## Surface a pending bare Escape now (the byte parser otherwise waits
  ## to see whether it starts a sequence).
  termctlParser.flush(d.parser)
  d.drainParser(sink)

proc tick*(d: var WinKeyDecoder; sink: var seq[TerminalEvent];
           now: MonoTime = getMonoTime()) =
  ## Age out a bare Escape after the byte parser's escape delay. The
  ## reader calls this whenever its wait for input times out.
  termctlParser.tick(d.parser, now)
  d.drainParser(sink)

proc decode*(d: var WinKeyDecoder; rec: WinKeyRecord;
             sink: var seq[TerminalEvent]) =
  ## Decode one key record, appending any events it completes to `sink`.
  ## Key-up records produce nothing (the POSIX byte stream carries press
  ## semantics only, and so does the Pilot harness).
  if not rec.keyDown:
    return
  if rec.isVtTranslated:
    d.feedUnit(rec.unicodeChar)
    d.drainParser(sink)
  else:
    # A record that kept its virtual key cannot continue an escape
    # sequence, so a pending bare Escape was a key press of its own.
    d.flush(sink)
    sink.add translateStructured(rec)
