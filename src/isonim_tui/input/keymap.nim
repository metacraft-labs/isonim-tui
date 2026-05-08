## isonim_tui/input/keymap.nim — named-key catalogue and
## name-to-bytes round-trip helpers.
##
## M4 ships the byte-level parser through `nim-termctl/parser.nim`; this
## module is the thin reverse map (and convenience canonical-name
## table) shared by tests and pilot tooling. Textual-equivalent names
## ("up", "ctrl+c", "shift+tab", "f5") are used everywhere the
## renderer talks about keys, so the byte parser, the synthetic
## `Pilot.press(...)` path, and the upstream key-binding system all
## agree.
##
## Charter: pure value types; no `ref`, no globals, no `cast`.

import std/strutils
import ../events

const
  ## The canonical Textual-style key name for every named key the byte
  ## parser can emit. Indexed by enum below; matches
  ## `parser.canonicalKeyName` exactly.
  namedKeyNames* = [
    "enter", "escape", "tab", "shift+tab", "backspace",
    "insert", "delete", "home", "end", "pageup", "pagedown",
    "up", "down", "left", "right",
    "f1", "f2", "f3", "f4", "f5", "f6",
    "f7", "f8", "f9", "f10", "f11", "f12"
  ]

proc isNamedKey*(name: string): bool =
  ## True if `name` is one of the canonical Textual names. Used by
  ## tooling that wants to disambiguate "press Enter" from "press a".
  for n in namedKeyNames:
    if n == name: return true
  false

proc bytesForNamedKey*(name: string): string =
  ## Reverse map: produce a representative byte sequence for the named
  ## key. Used by the corpus generator and by the recorder for "push
  ## this canonical sequence". Returns the empty string for keys
  ## without a representative encoding.
  case name.toLowerAscii
  of "enter":     "\x0D"
  of "escape":    "\x1B"
  of "tab":       "\x09"
  of "shift+tab": "\x1B[Z"
  of "backspace": "\x7F"
  of "insert":    "\x1B[2~"
  of "delete":    "\x1B[3~"
  of "home":      "\x1B[H"
  of "end":       "\x1B[F"
  of "pageup":    "\x1B[5~"
  of "pagedown":  "\x1B[6~"
  of "up":        "\x1B[A"
  of "down":      "\x1B[B"
  of "left":      "\x1B[D"
  of "right":     "\x1B[C"
  of "f1":        "\x1BOP"
  of "f2":        "\x1BOQ"
  of "f3":        "\x1BOR"
  of "f4":        "\x1BOS"
  of "f5":        "\x1B[15~"
  of "f6":        "\x1B[17~"
  of "f7":        "\x1B[18~"
  of "f8":        "\x1B[19~"
  of "f9":        "\x1B[20~"
  of "f10":       "\x1B[21~"
  of "f11":       "\x1B[23~"
  of "f12":       "\x1B[24~"
  else:           ""

proc bytesForCtrlLetter*(letter: char): string =
  ## Map an ASCII letter to its Ctrl+letter byte (Ctrl+A=0x01,
  ## Ctrl+Z=0x1A). Caller passes either upper or lower case.
  let u = letter.toUpperAscii
  if u in {'A'..'Z'}:
    $char(byte(u) - byte('A') + 1)
  else:
    ""

proc renderKeyName*(name: string; mods: set[Modifier]): string =
  ## Same routine `parser.translate` uses internally; exposed for
  ## tests that want to construct expected names without reaching into
  ## parser internals.
  result = ""
  if modCtrl in mods: result.add "ctrl+"
  if modAlt in mods: result.add "alt+"
  if modShift in mods and name != "tab":
    result.add "shift+"
  if modMeta in mods: result.add "meta+"
  if modSuper in mods: result.add "super+"
  if modHyper in mods: result.add "hyper+"
  result.add name
