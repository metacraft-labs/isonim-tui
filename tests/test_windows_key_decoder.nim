## test_windows_key_decoder — the WindowsDriver's key-record decoder.
##
## The driver enables `ENABLE_VIRTUAL_TERMINAL_INPUT`. In that mode a
## real Windows console (conhost) replaces the records of the keys its VT
## module translates with records carrying the VT input text, one UTF-16
## unit each, built as `SynthesizeKeyEvent(true, 1, 0, 0, wch, 0)`:
## virtual key 0, scan code 0, no control-key state (microsoft/terminal
## `src/host/inputBuffer.cpp`, `InputBuffer::_writeString`, at
## 92f2a771057116d4313a5f1ef7801d9e04902a85). Wine's console does not do
## this, which is how a decoder that only understood the structured
## shape passed under Wine and failed on a real Windows runner: the
## Ctrl+C written by `test_windows_driver_keys_round_trip` came back as
## a lone 0x03 with no Ctrl bit.
##
## These cases call the decoder with both record shapes directly, so
## they run on every host and do not depend on which keys a particular
## conhost build translates. The shapes are the ones conhost produces;
## `WinKeyRecord` is the decoder's own input type, not a stand-in for a
## collaborator, so nothing here is mocked. The real console round trip
## stays in the `test_windows_driver_*` tests.

import std/[monotimes, times, unittest]

import isonim_tui/events
import isonim_tui/drivers/windows_key_decoder

proc vt(unit: uint16): WinKeyRecord =
  ## A record as conhost synthesizes it from VT input text.
  WinKeyRecord(keyDown: true, virtualKeyCode: 0, virtualScanCode: 0,
               unicodeChar: unit, controlKeyState: 0)

proc vtText(s: string): seq[WinKeyRecord] =
  for c in s:
    result.add vt(uint16(ord(c)))

proc structured(vk: uint16; ch: uint16; ctrlState = 0'u32;
                keyDown = true): WinKeyRecord =
  ## A record that kept its virtual key (a key conhost left alone, or
  ## any key when VT input is off).
  WinKeyRecord(keyDown: keyDown, virtualKeyCode: vk, virtualScanCode: 0x2E,
               unicodeChar: ch, controlKeyState: ctrlState)

proc decodeAll(recs: openArray[WinKeyRecord]; flush = true):
    seq[TerminalEvent] =
  var d = initWinKeyDecoder()
  for r in recs:
    d.decode(r, result)
  if flush:
    d.flush(result)

proc describe(evs: seq[TerminalEvent]): string =
  ## One line per event, so a failed check shows what was decoded.
  for e in evs:
    result.add "[kind=" & $e.key.kind & " key=" & e.key.key.repr &
      " rune=" & $e.key.rune & " mods=" & $e.key.modifiers & "] "

template checkKey(ev: TerminalEvent; expectedKind: KeyKind;
                  expectedKey: string; expectedMods: set[Modifier]) =
  check ev.kind == ekKey
  check ev.`type` == "keydown"
  check ev.key.kind == expectedKind
  check ev.key.key == expectedKey
  # Bind the set first: `check` cannot infer the type of a bare `{}`.
  let wantMods: set[Modifier] = expectedMods
  check ev.key.modifiers == wantMods

suite "WindowsDriver key-record decoder":

  test "VT-translated Ctrl+C (0x03, no Ctrl bit, vk 0) is Ctrl+c":
    let evs = decodeAll([vt(0x03)])
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkChar, "c", {modCtrl})
    check evs[0].key.rune == uint32(ord('c'))

  test "Ctrl+C record with vk 'C' but no Ctrl bit is Ctrl+c":
    let evs = decodeAll([structured(uint16(ord('C')), 0x03)])
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkChar, "c", {modCtrl})

  test "Ctrl+C record with vk 'C' and the Ctrl bit is Ctrl+c":
    let evs = decodeAll([structured(uint16(ord('C')), 0x03,
                                    LeftCtrlPressed)])
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkChar, "c", {modCtrl})

  test "every VT-translated C0 letter is Ctrl+letter":
    for b in [0x01, 0x02, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0E, 0x0F,
              0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19,
              0x1A]:
      let evs = decodeAll([vt(uint16(b))])
      checkpoint "byte " & $b & ": " & describe(evs)
      check evs.len == 1
      checkKey(evs[0], kkChar, $char(ord('a') + b - 1), {modCtrl})

  test "VT-translated Enter, Tab and Backspace are named keys":
    let evs = decodeAll(vtText("\r\t\x08\x7F"))
    checkpoint describe(evs)
    check evs.len == 4
    checkKey(evs[0], kkNamed, "enter", {})
    checkKey(evs[1], kkNamed, "tab", {})
    checkKey(evs[2], kkNamed, "backspace", {})
    checkKey(evs[3], kkNamed, "backspace", {})

  test "a VT-translated lone Escape surfaces on flush":
    var d = initWinKeyDecoder()
    var evs: seq[TerminalEvent] = @[]
    d.decode(vt(0x1B), evs)
    # It could still start a sequence, so nothing is emitted yet.
    check evs.len == 0
    d.flush(evs)
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkNamed, "escape", {})

  test "a VT-translated lone Escape ages out on tick":
    var d = initWinKeyDecoder()
    var evs: seq[TerminalEvent] = @[]
    d.decode(vt(0x1B), evs)
    d.tick(evs, getMonoTime())
    check evs.len == 0
    d.tick(evs, getMonoTime() + initDuration(seconds = 1))
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkNamed, "escape", {})

  test "VT-translated arrow and function keys decode as on POSIX":
    let evs = decodeAll(vtText("\e[A\eOP\e[1;5C\e[Z"))
    checkpoint describe(evs)
    check evs.len == 4
    checkKey(evs[0], kkNavigation, "up", {})
    checkKey(evs[1], kkFunction, "f1", {})
    checkKey(evs[2], kkNavigation, "right", {modCtrl})
    checkKey(evs[3], kkNamed, "tab", {modShift})

  test "VT-translated printable characters and space":
    let evs = decodeAll(vtText("a Z"))
    checkpoint describe(evs)
    check evs.len == 3
    checkKey(evs[0], kkChar, "a", {})
    checkKey(evs[1], kkNamed, "space", {})
    checkKey(evs[2], kkChar, "Z", {})

  test "VT-translated Alt+x is ESC x":
    let evs = decodeAll(vtText("\ex"))
    checkpoint describe(evs)
    check evs.len == 1
    checkKey(evs[0], kkChar, "x", {modAlt})

  test "a VT-translated surrogate pair is one character":
    # U+1F600 is D83D DE00 in UTF-16; conhost writes one record per unit.
    let evs = decodeAll([vt(0xD83D), vt(0xDE00)])
    checkpoint describe(evs)
    check evs.len == 1
    check evs[0].key.kind == kkChar
    check evs[0].key.rune == 0x1F600'u32
    check evs[0].key.key == "\u{1F600}"

  test "the round-trip test's records as the CI host's conhost delivered them":
    # 'a' and Enter kept their records; Ctrl+C was replaced by 0x03.
    let evs = decodeAll([structured(uint16(ord('A')), uint16(ord('a'))),
                         structured(VkReturn, 0),
                         vt(0x03)])
    checkpoint describe(evs)
    check evs.len == 3
    checkKey(evs[0], kkChar, "a", {})
    checkKey(evs[1], kkNamed, "enter", {})
    checkKey(evs[2], kkChar, "c", {modCtrl})

  test "a pending Escape is emitted before a following structured key":
    let evs = decodeAll([vt(0x1B), structured(VkUp, 0)], flush = false)
    checkpoint describe(evs)
    check evs.len == 2
    checkKey(evs[0], kkNamed, "escape", {})
    checkKey(evs[1], kkNavigation, "up", {})

  test "structured named keys, modifiers and key-up records":
    let evs = decodeAll([structured(VkF1 + 4, 0),
                         structured(VkLeft, 0, ShiftPressed or
                                    RightAltPressed),
                         structured(uint16(ord('A')), uint16(ord('a')),
                                    keyDown = false)])
    checkpoint describe(evs)
    check evs.len == 2
    checkKey(evs[0], kkFunction, "f5", {})
    checkKey(evs[1], kkNavigation, "left", {modShift, modAlt})
