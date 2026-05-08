## test_input_kitty_protocol
##
## M4 verification: Kitty progressive-enhancement keyboard protocol
## (`CSI codepoint ; mods : event-type u`). When enabled, the parser
## decodes:
##
##   * Plain key press: `\x1b[97;1u` -> 'a' press (codepoint 97 = 'a',
##     mods=1 = none, no event-type sub-param defaults to press).
##   * Modifier-encoded press: `\x1b[97;5u` -> Ctrl+a (mods=5 = Ctrl).
##   * Key release: `\x1b[97;1:3u` -> 'a' release (event-type 3).
##   * Repeat: `\x1b[97;1:2u` -> 'a' repeat.
##
## NOTE on the spec wording: the milestone text shows
## `\x1b[a;1;1u`. Kitty's actual wire format uses the *codepoint*
## (97 for 'a'), not the literal letter; the `a` in the spec is
## shorthand for "the codepoint of letter a". We test the byte form
## the parser actually sees.

import std/[unittest]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseKitty(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  enableKittyKeyboard(ip)
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: Kitty extended-keyboard protocol":

  test "Plain 'a' press via CSI 97 ; 1 u":
    let evs = parseKitty("\x1b[97;1u")
    check evs.len == 1
    check evs[0].kind == ekKey
    check evs[0].`type` == "keydown"
    check evs[0].key.kind == kkChar
    check evs[0].key.rune == 0x61'u32  # 'a'

  test "Ctrl+a press via CSI 97 ; 5 u (mods=5 = Ctrl)":
    let evs = parseKitty("\x1b[97;5u")
    check evs.len == 1
    check evs[0].key.modifiers == {modCtrl}
    check evs[0].key.rune == 0x61'u32

  test "Shift+A press via CSI 65 ; 2 u (mods=2 = Shift)":
    let evs = parseKitty("\x1b[65;2u")
    check evs.len == 1
    check evs[0].key.modifiers == {modShift}
    check evs[0].key.rune == 0x41'u32  # 'A'

  test "Alt+a via CSI 97 ; 3 u":
    let evs = parseKitty("\x1b[97;3u")
    check evs.len == 1
    check evs[0].key.modifiers == {modAlt}

  test "Key release: 'a' release via CSI 97 ; 1 : 3 u":
    let evs = parseKitty("\x1b[97;1:3u")
    check evs.len == 1
    check evs[0].`type` == "keyup"
    check evs[0].key.rune == 0x61'u32

  test "Key repeat: 'a' repeat via CSI 97 ; 1 : 2 u":
    let evs = parseKitty("\x1b[97;1:2u")
    check evs.len == 1
    # Repeat surfaces as keydown in our public model (Textual collapses
    # press+repeat to keydown; release is a separate event).
    check evs[0].`type` == "keydown"

  test "Three Kitty events in a row":
    let evs = parseKitty("\x1b[97;1u\x1b[98;1u\x1b[99;1u")
    check evs.len == 3
    check evs[0].key.rune == 0x61'u32  # 'a'
    check evs[1].key.rune == 0x62'u32  # 'b'
    check evs[2].key.rune == 0x63'u32  # 'c'

  test "Special key codepoints (Enter via Kitty)":
    # Kitty sends Enter as codepoint 13 (CR). The parser maps this back
    # to kcEnter so the canonical name is "enter".
    let evs = parseKitty("\x1b[13;1u")
    check evs.len == 1
    check evs[0].key.key == "enter"

  test "Disabled by default: CSI 97;1u without enableKittyKeyboard":
    # When the parser hasn't been told the terminal supports Kitty
    # mode, `CSI 97;1u` is still decoded (the parser dispatches the
    # `u` final regardless — `enableKittyKeyboard` is used as a hint
    # for future strict-mode behaviour but currently doesn't gate
    # decoding). Document the current behaviour explicitly so a
    # regression is caught if we tighten this later.
    var ip = initInputParser()
    ip.feed("\x1b[97;1u")
    ip.flush()
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.rune == 0x61'u32
