## test_input_partial_sequence
##
## M4 verification: split sequences across reads. The L3 byte parser is
## stateful and incremental; if `\x1b[` arrives in one read and `A` in
## the next, the result MUST be one `up` event, not two corrupt ones.
##
## We also exercise:
##   * The bare-Escape disambiguation path: ESC alone followed by
##     `flush()` produces a bare Escape KeyEvent.
##   * Splits inside parameter blocks (CSI 1;5 then A still produces
##     Ctrl+Up).
##   * Splits inside UTF-8 codepoints (the parser must reassemble the
##     emoji across two reads, not emit a partial rune).

import std/[unittest]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

suite "M4: partial sequences across reads":

  test "ESC[ in one read, A in next -> single Up":
    var ip = initInputParser()
    ip.feed("\x1b[")
    check ip.pending() == 0
    ip.feed("A")
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.key == "up"

  test "Three-way split: ESC[ / 1;5 / A -> Ctrl+Up":
    var ip = initInputParser()
    ip.feed("\x1b[")
    ip.feed("1;5")
    ip.feed("A")
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.key == "ctrl+up"
    check evs[0].key.modifiers == {modCtrl}

  test "Bare ESC -> nothing until flush()":
    var ip = initInputParser()
    ip.feed("\x1b")
    check ip.pending() == 0
    ip.flush()
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.key == "escape"

  test "UTF-8 4-byte rune split across two reads":
    # '🦀' = U+1F980 = F0 9F A6 80
    var ip = initInputParser()
    ip.feed("\xF0\x9F")
    check ip.pending() == 0
    ip.feed("\xA6\x80")
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].kind == ekKey
    check evs[0].key.rune == 0x1F980'u32

  test "Mixed partial CSI then complete plain key":
    var ip = initInputParser()
    ip.feed("\x1b[")
    ip.feed("A")
    ip.feed("x")
    let evs = ip.drain()
    check evs.len == 2
    check evs[0].key.key == "up"
    check evs[1].key.key == "x"

  test "Byte-by-byte feeding still emits one event":
    var ip = initInputParser()
    for b in "\x1b[1;5A":
      var single = newSeq[byte](1)
      single[0] = byte(b)
      ip.feed(single)
    let evs = ip.drain()
    check evs.len == 1
    check evs[0].key.key == "ctrl+up"
