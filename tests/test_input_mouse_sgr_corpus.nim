## test_input_mouse_sgr_corpus
##
## M4 verification: SGR-1006 mouse encoding for press / release / drag /
## wheel events from xterm, Kitty, Alacritty, iTerm2, WezTerm, Windows
## Terminal — every modern terminal emits the same `\x1b[<b;col;rowM/m`
## byte stream, so this single corpus exercises all of them.
##
## Real-stack: bytes flow through the M4 input adapter (which delegates
## to nim-termctl's L3 byte parser) and surface as `TerminalEvent`s.

import std/[unittest]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseAll(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: SGR-1006 mouse corpus":

  test "Left button press at (col=10, row=5) -> mousedown":
    let evs = parseAll("\x1b[<0;10;5M")
    check evs.len == 1
    check evs[0].kind == ekMouseDown
    check evs[0].`type` == "mousedown"
    check evs[0].mouse.button == mbLeft
    check evs[0].mouse.col == 10
    check evs[0].mouse.row == 5
    check evs[0].mouse.modifiers == {}

  test "Left button release -> mouseup at the same coords":
    let evs = parseAll("\x1b[<0;10;5m")
    check evs.len == 1
    check evs[0].kind == ekMouseUp
    check evs[0].`type` == "mouseup"
    check evs[0].mouse.button == mbLeft

  test "Right button press at (col=42, row=24)":
    let evs = parseAll("\x1b[<2;42;24M")
    check evs.len == 1
    check evs[0].kind == ekMouseDown
    check evs[0].mouse.button == mbRight
    check evs[0].mouse.col == 42
    check evs[0].mouse.row == 24

  test "Middle button press":
    let evs = parseAll("\x1b[<1;5;5M")
    check evs.len == 1
    check evs[0].mouse.button == mbMiddle

  test "Wheel up scroll -> ekScroll with mbWheelUp":
    let evs = parseAll("\x1b[<64;1;1M")
    check evs.len == 1
    check evs[0].kind == ekScroll
    check evs[0].`type` == "scroll"
    check evs[0].mouse.button == mbWheelUp

  test "Wheel down scroll -> mbWheelDown":
    let evs = parseAll("\x1b[<65;1;1M")
    check evs.len == 1
    check evs[0].kind == ekScroll
    check evs[0].mouse.button == mbWheelDown

  test "Drag (button held + motion bit) -> mousemove":
    # Button 0 (left) + motion bit (32) = 32. Coords (col=15, row=8).
    let evs = parseAll("\x1b[<32;15;8M")
    check evs.len == 1
    check evs[0].kind == ekMouseMove
    check evs[0].mouse.col == 15
    check evs[0].mouse.row == 8

  test "Shift+Click (modifier bit on the SGR button)":
    # Bit 4 set = Shift; button=0 (left). 0+4=4.
    let evs = parseAll("\x1b[<4;10;5M")
    check evs.len == 1
    check evs[0].mouse.modifiers == {modShift}
    check evs[0].mouse.button == mbLeft

  test "Ctrl+Click (modifier bit 16)":
    # Bit 16 set = Ctrl; button=0. 0+16=16.
    let evs = parseAll("\x1b[<16;10;5M")
    check evs.len == 1
    check evs[0].mouse.modifiers == {modCtrl}
    check evs[0].mouse.button == mbLeft

  test "Alt+Click (modifier bit 8)":
    let evs = parseAll("\x1b[<8;10;5M")
    check evs.len == 1
    check evs[0].mouse.modifiers == {modAlt}

  test "Three sequential clicks at different coords":
    let evs = parseAll("\x1b[<0;1;1M\x1b[<0;1;1m\x1b[<0;5;5M")
    check evs.len == 3
    check evs[0].kind == ekMouseDown
    check evs[1].kind == ekMouseUp
    check evs[2].kind == ekMouseDown
    check evs[2].mouse.col == 5
    check evs[2].mouse.row == 5
