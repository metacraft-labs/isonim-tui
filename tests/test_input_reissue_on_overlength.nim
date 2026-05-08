## test_input_reissue_on_overlength
##
## M4 verification: a 33+ byte CSI prefix with no matching final
## terminator MUST NOT silently lose the bytes. Per Textual's
## `_xterm_parser` (32-byte sanity limit), the parser falls back to
## per-character key events: ESC, '[', and one keydown per accumulated
## parameter byte.
##
## This catches a corner case where:
##   * The user's terminal sent malformed bytes (rare).
##   * A driver bug produced an unterminated CSI (rarer).
##   * A test fixture was authored incorrectly.
##
## Without reissue, those bytes vanish; with reissue, the user sees
## the keystrokes that produced them and the driver can recover.

import std/[unittest, strutils]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseAll(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: reissue on overlength":

  test "32-byte parameter prefix without final -> per-char fallback":
    # Build `\x1b[` followed by 33 digit bytes and NO final byte.
    # The parser's 32-byte CSI sanity limit triggers reissue: an ESC
    # keydown, a '[' keydown, then one keydown per accumulated byte.
    let payload = repeat('1', 33)
    let evs = parseAll("\x1b[" & payload)
    # 1 ESC + 1 '[' + 33 '1' = 35 events.
    check evs.len == 35
    check evs[0].key.key == "escape"
    check evs[1].key.key == "["
    check evs[1].key.kind == kkChar
    for i in 2 ..< evs.len:
      check evs[i].key.key == "1"

  test "Under-limit CSI still resolves normally":
    # 30 digit bytes is below the 32-byte threshold. The parser does
    # NOT trigger reissue; it accepts the eventual final byte.
    let payload = repeat('1', 30)
    let evs = parseAll("\x1b[" & payload & "A")
    # Up arrow with a junk modifier mask gets parsed; the body has
    # too many garbage params for a real arrow event but the parser
    # processes it. We only check it didn't reissue (no ESC bare key).
    check evs.len == 1
    # `A` final byte means cursor-up; the param mask resolves to no
    # mods (since the digit sequence isn't `;`-separated and parses
    # as one giant integer modifier).
    check evs[0].key.key.endsWith("up")

  test "Over-limit then a clean key after recovery":
    # The reissue puts the parser back in ground state, so a follow-up
    # keystroke parses normally.
    let payload = repeat('1', 33)
    let evs = parseAll("\x1b[" & payload & "x")
    # 1 ESC + 1 '[' + 33 '1' = 35 + 1 'x' = 36 events.
    check evs.len == 36
    check evs[^1].key.key == "x"
