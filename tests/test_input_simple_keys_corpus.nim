## test_input_simple_keys_corpus
##
## M4 verification: feed the byte streams a TUI receives for plain
## keystrokes (a, Ctrl+C), function keys (F1, F5), and arrow keys (Up)
## across the major terminal categories — and assert the typed events
## isonim-tui produces match the goldens exactly.
##
## Real-stack: bytes flow through `nim_termctl.parser` (the L3 byte
## parser ported under the IsoNim-TUI plan) into `isonim_tui.input.parser`
## (the M4 adapter that translates them to `TerminalEvent`).
##
## No mocks. Every assertion is on a typed event from the real
## parser — no by-hand byte parsing in the test.

import std/[unittest, options]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseAll(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: input simple keys corpus":

  test "ASCII letter -> char keydown":
    let evs = parseAll("a")
    check evs.len == 1
    check evs[0].kind == ekKey
    check evs[0].`type` == "keydown"
    check evs[0].key.kind == kkChar
    check evs[0].key.key == "a"
    check evs[0].key.rune == 0x61'u32
    check evs[0].key.modifiers == {}

  test "Ctrl+C -> char keydown with modCtrl":
    # Ctrl+C is 0x03 (the ETX control byte every terminal sends).
    let evs = parseAll("\x03")
    check evs.len == 1
    check evs[0].kind == ekKey
    check evs[0].key.key == "ctrl+c"
    check evs[0].key.rune == 0x63'u32  # 'c'
    check evs[0].key.modifiers == {modCtrl}

  test "Tab / Enter / Backspace -> named keys":
    let evs = parseAll("\x09\x0D\x7F")
    check evs.len == 3
    check evs[0].key.key == "tab"
    check evs[0].key.kind == kkNamed
    check evs[1].key.key == "enter"
    check evs[1].key.kind == kkNamed
    check evs[2].key.key == "backspace"
    check evs[2].key.kind == kkNamed

  test "F1-F4 (SS3 / VT100 form, common across xterm/Linux console)":
    let evs = parseAll("\x1bOP\x1bOQ\x1bOR\x1bOS")
    check evs.len == 4
    check evs[0].key.key == "f1"
    check evs[0].key.kind == kkFunction
    check evs[1].key.key == "f2"
    check evs[2].key.key == "f3"
    check evs[3].key.key == "f4"

  test "F5/F6/F7/F8 (CSI ~ form)":
    let evs = parseAll("\x1b[15~\x1b[17~\x1b[18~\x1b[19~")
    check evs.len == 4
    check evs[0].key.key == "f5"
    check evs[1].key.key == "f6"
    check evs[2].key.key == "f7"
    check evs[3].key.key == "f8"

  test "F11/F12 (CSI ~ form)":
    let evs = parseAll("\x1b[23~\x1b[24~")
    check evs.len == 2
    check evs[0].key.key == "f11"
    check evs[1].key.key == "f12"

  test "Arrow keys (CSI form, every terminal)":
    let evs = parseAll("\x1b[A\x1b[B\x1b[C\x1b[D")
    check evs.len == 4
    check evs[0].key.key == "up"
    check evs[0].key.kind == kkNavigation
    check evs[1].key.key == "down"
    check evs[2].key.key == "right"
    check evs[3].key.key == "left"

  test "Home/End/PgUp/PgDn (CSI ~ form)":
    let evs = parseAll("\x1b[1~\x1b[4~\x1b[5~\x1b[6~")
    check evs.len == 4
    check evs[0].key.key == "home"
    check evs[1].key.key == "end"
    check evs[2].key.key == "pageup"
    check evs[3].key.key == "pagedown"

  test "Modifier-encoded arrow (Ctrl+Up via CSI 1;5A)":
    let evs = parseAll("\x1b[1;5A")
    check evs.len == 1
    check evs[0].key.key == "ctrl+up"
    check evs[0].key.modifiers == {modCtrl}

  test "Modifier-encoded arrow (Alt+Up via CSI 1;3A)":
    let evs = parseAll("\x1b[1;3A")
    check evs.len == 1
    check evs[0].key.key == "alt+up"
    check evs[0].key.modifiers == {modAlt}

  test "Shift+Tab (BackTab) -> shift+tab (canonical)":
    # CSI Z is universally Shift+Tab; the canonical name encodes
    # the modifier so it's a single-string lookup.
    let evs = parseAll("\x1b[Z")
    check evs.len == 1
    check evs[0].key.key == "shift+tab"

  test "Alt+letter via ESC-prefix":
    let evs = parseAll("\x1ba")
    check evs.len == 1
    check evs[0].key.key == "alt+a"
    check evs[0].key.modifiers == {modAlt}

  test "Bare Escape resolves on flush":
    var ip = initInputParser()
    ip.feed("\x1b")
    # Without flush(), parser sits in psEscaped and emits nothing.
    check ip.pending() == 0
    ip.flush()
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.key == "escape"

  test "UTF-8 multi-byte rune across one feed":
    # 'ä' = 0xC3 0xA4 (U+00E4).
    let evs = parseAll("\xC3\xA4")
    check evs.len == 1
    check evs[0].kind == ekKey
    check evs[0].key.kind == kkChar
    check evs[0].key.rune == 0x00E4'u32

  test "Three-key sequence emits three events in order":
    let evs = parseAll("abc")
    check evs.len == 3
    check evs[0].key.key == "a"
    check evs[1].key.key == "b"
    check evs[2].key.key == "c"
