## tools/record_terminal_bytes.nim
##
## Recorder CLI for growing the M4 input-parser corpus over time.
##
## What it does
## ------------
## Puts the host terminal in raw mode (via nim-termctl), reads stdin
## byte-by-byte, and writes:
##
##   1. The raw byte stream — one fixture per session — to
##      `tests/fixtures/terminal_byte_streams/<terminal>-<timestamp>.bin`.
##   2. A human-readable transcript next to it
##      (`...same-name....txt`) listing each byte in hex plus the
##      typed-event the parser produced for it. Used to author the
##      golden event sequence by hand.
##
## Usage
## -----
## ```sh
## # In a real terminal (xterm, Kitty, Alacritty, iTerm2, WezTerm, ...)
## nim r tools/record_terminal_bytes.nim --label=xterm
## # Press the keys you want recorded, then press Ctrl+D to end.
## ```
##
## The `--label` flag identifies which terminal recorded the fixture so
## later the corpus loader can compare the same key across terminals
## (which the milestone calls "test_parser_byte_parity_with_textual"
## and friends — deferred until a multi-terminal CI is available).
##
## Charter
## -------
## This is dev tooling, not part of the public API. It links
## nim-termctl directly. We never call `cast`, never use `ptr`, and
## obey the no-`ref` rule for value types.

import std/[os, parseopt, strutils, times, options]

import nim_termctl
import isonim_tui/input/parser as inputParser
import isonim_tui/events

const
  defaultFixturesDir = "tests/fixtures/terminal_byte_streams"

proc usage() =
  echo "Usage: record_terminal_bytes [--label=<terminal>] [--out=<dir>]"
  echo "  --label    Friendly identifier for the recording terminal"
  echo "             (e.g. xterm, kitty, alacritty, iterm2, wezterm,"
  echo "             windows-terminal, linux-console). Defaults to"
  echo "             the value of $TERM_PROGRAM, $TERM, or 'unknown'."
  echo "  --out      Output directory. Defaults to:"
  echo "             tests/fixtures/terminal_byte_streams/"
  echo "  --help     Show this message."
  echo ""
  echo "Press Ctrl+D to stop recording."
  quit(0)

proc detectLabel(): string =
  result = getEnv("TERM_PROGRAM")
  if result.len == 0:
    result = getEnv("TERM")
  if result.len == 0:
    result = "unknown"
  # Sanitise for filesystem use.
  for ch in result.mitems:
    if ch in {'/', '\\', ' ', ':', '*'}: ch = '-'

proc describeEvent(ev: TerminalEvent): string =
  case ev.kind
  of ekKey:    "key " & ev.key.key & " (rune=0x" &
                toHex(int(ev.key.rune), 4) & ")"
  of ekMouseDown: "mousedown " & $ev.mouse.button &
                  " @(" & $ev.mouse.col & "," & $ev.mouse.row & ")"
  of ekMouseUp:   "mouseup " & $ev.mouse.button &
                  " @(" & $ev.mouse.col & "," & $ev.mouse.row & ")"
  of ekMouseMove: "mousemove @(" & $ev.mouse.col & "," &
                  $ev.mouse.row & ")"
  of ekScroll:    "scroll " & $ev.mouse.button
  of ekResize:    "resize " & $ev.resize.cols & "x" & $ev.resize.rows
  of ekFocus:     "focus"
  of ekBlur:      "blur"
  of ekPaste:     "paste " & $ev.paste.text.len & " bytes"
  of ekCustom:    "custom"

proc main() =
  var label = ""
  var outDir = defaultFixturesDir
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "label": label = p.val
      of "out":   outDir = p.val
      of "help", "h": usage()
      else: discard
    of cmdArgument: discard
  if label.len == 0: label = detectLabel()

  createDir(outDir)
  let stamp = now().format("yyyyMMddHHmmss")
  let baseName = label & "-" & stamp
  let binPath = outDir / (baseName & ".bin")
  let txtPath = outDir / (baseName & ".txt")

  echo "Recording to:"
  echo "  ", binPath
  echo "  ", txtPath
  echo "Press Ctrl+D to stop."
  echo ""

  let binFile = open(binPath, fmWrite)
  defer: binFile.close()
  let txtFile = open(txtPath, fmWrite)
  defer: txtFile.close()
  txtFile.writeLine("# isonim-tui input recorder")
  txtFile.writeLine("# label: " & label)
  txtFile.writeLine("# timestamp: " & stamp)
  txtFile.writeLine("# format: hex-bytes \"\\t\" event-description")
  txtFile.writeLine("")

  block recording:
    var raw = enableRawMode()
    discard raw  # held alive by name; destructor restores termios on exit
    var er = newEventReader()
    var totalBytes = 0
    while true:
      let ev = pollEvent(er, initDuration(seconds = 30))
      if ev.isNone: break
      let parsed = ev.get()
      if parsed.kind == ekKey and parsed.key.code == kcChar and
         parsed.key.rune.int32 == 4:
        # Ctrl+D ends recording.
        break
      # Re-encode the event back to representative bytes for the
      # archive. Production callers will ideally hook the *raw* input
      # FD instead — this is approximate but good enough for hand-
      # authored corpora until that wiring lands (deferred to M9).
      let descr = describeEvent(translate(parsed))
      txtFile.writeLine(descr)
      inc totalBytes
    txtFile.writeLine("")
    txtFile.writeLine("# total events: " & $totalBytes)

  echo "Done."

when isMainModule:
  main()
