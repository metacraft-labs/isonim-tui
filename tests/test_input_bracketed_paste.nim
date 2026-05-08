## test_input_bracketed_paste
##
## M4 verification: `\x1b[200~` opens a paste, `\x1b[201~` closes it, and
## *every byte in between* — even bytes that look like CSI sequences —
## belongs to the paste payload.
##
## Real-stack: bytes flow through the M4 input adapter, and the parser
## must emit exactly one `PasteEvent` covering the whole payload.

import std/[unittest, strutils]
import isonim_tui/events
import isonim_tui/input/parser as inputParser

proc parseAll(s: string): seq[TerminalEvent] =
  var ip = initInputParser()
  ip.feed(s)
  ip.flush()
  ip.drain()

suite "M4: bracketed paste":

  test "Plain ASCII paste":
    let evs = parseAll("\x1b[200~hello\x1b[201~")
    check evs.len == 1
    check evs[0].kind == ekPaste
    check evs[0].`type` == "paste"
    check evs[0].paste.text == "hello"

  test "Multi-line paste (newlines preserved)":
    let payload = "line1\nline2\nline3"
    let evs = parseAll("\x1b[200~" & payload & "\x1b[201~")
    check evs.len == 1
    check evs[0].paste.text == payload

  test "Paste containing CSI-like sequences inside payload":
    # Bytes that LOOK like cursor moves but are actually pasted text
    # (the user copied an escape sequence from somewhere). The parser
    # must NOT emit them as key/cursor events; they're paste payload.
    let payload = "before\x1b[Aafter"
    let evs = parseAll("\x1b[200~" & payload & "\x1b[201~")
    check evs.len == 1
    check evs[0].kind == ekPaste
    check evs[0].paste.text == payload

  test "Paste containing the start-of-paste-like bytes":
    # User pastes "[200~" as literal text (i.e. someone wrote a
    # docstring about bracketed paste and copied it). The leading ESC
    # would normally start a sequence; inside paste mode it doesn't.
    let payload = "code: [200~ then [201~"
    let evs = parseAll("\x1b[200~" & payload & "\x1b[201~")
    check evs.len == 1
    check evs[0].paste.text == payload

  test "Empty paste":
    let evs = parseAll("\x1b[200~\x1b[201~")
    check evs.len == 1
    check evs[0].kind == ekPaste
    check evs[0].paste.text == ""

  test "Key before paste, key after paste":
    let evs = parseAll("a\x1b[200~text\x1b[201~b")
    check evs.len == 3
    check evs[0].kind == ekKey
    check evs[0].key.key == "a"
    check evs[1].kind == ekPaste
    check evs[1].paste.text == "text"
    check evs[2].kind == ekKey
    check evs[2].key.key == "b"

  test "Large paste (1000 chars) emits one event":
    let payload = repeat('x', 1000)
    let evs = parseAll("\x1b[200~" & payload & "\x1b[201~")
    check evs.len == 1
    check evs[0].paste.text.len == 1000
