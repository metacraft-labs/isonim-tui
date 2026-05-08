## test_input_in_band_resize
##
## M4 verification: Kitty's in-band window-size events
## (`CSI 48 ; height ; width ; pixel_height ; pixel_width t`) surface
## as `ResizeEvent`s on the parser's queue. Drivers that opt in via
## DECSET 2048 receive resizes interleaved with key/mouse events
## instead of via the SIGWINCH signal handler.
##
## NOTE on spec wording: the milestone text reads
## `\x1b[48;100;30;800;600t` produces "ResizeEvent(width=100,
## height=30, pixel_width=800, pixel_height=600)". Kitty's actual
## wire protocol orders the parameters as
## `48 ; height ; width ; pixel_height ; pixel_width` (height first).
## nim-termctl follows Kitty's wire spec; this test uses the wire
## form. The width/height label flip in the milestone is a
## documentation-side typo, not a parser bug — the bytes on the wire
## are still parsed correctly per Kitty's published protocol.

import std/[unittest]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseAll(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: in-band resize (Kitty CSI 48 t)":

  test "Wire form CSI 48;30;100;600;800t -> ResizeEvent(cols=100, rows=30)":
    let evs = parseAll("\x1b[48;30;100;600;800t")
    check evs.len == 1
    check evs[0].kind == ekResize
    check evs[0].`type` == "resize"
    check evs[0].resize.cols == 100
    check evs[0].resize.rows == 30

  test "Three-param form (no pixel info) still surfaces a resize":
    # CSI 48;rows;cols t — older terminals omit the pixel-size suffix.
    let evs = parseAll("\x1b[48;24;80t")
    check evs.len == 1
    check evs[0].kind == ekResize
    check evs[0].resize.rows == 24
    check evs[0].resize.cols == 80

  test "Resize interleaved with keystrokes":
    let evs = parseAll("a\x1b[48;25;120tb")
    check evs.len == 3
    check evs[0].kind == ekKey
    check evs[0].key.key == "a"
    check evs[1].kind == ekResize
    check evs[1].resize.rows == 25
    check evs[1].resize.cols == 120
    check evs[2].kind == ekKey
    check evs[2].key.key == "b"

  test "Two consecutive resizes":
    let evs = parseAll("\x1b[48;20;80t\x1b[48;30;100t")
    check evs.len == 2
    check evs[0].kind == ekResize
    check evs[0].resize.rows == 20
    check evs[0].resize.cols == 80
    check evs[1].resize.rows == 30
    check evs[1].resize.cols == 100
