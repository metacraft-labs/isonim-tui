## Caret — where typed text goes, and in what shape.
##
## A text field in a GUI draws its own caret: a thin bar while it inserts, a
## block while it overwrites. A terminal has exactly one caret — its own
## cursor — and most terminals let an application choose its SHAPE with
## DECSCUSR (`CSI Ps SP q`): 2 a steady block, 4 a steady underline, 6 a
## steady bar. An application that puts the terminal's cursor where the text
## goes, in the right shape, gets the native caret (blinking as the user's
## terminal blinks it, drawn by the terminal's own renderer, read by screen
## readers).
##
## Not every terminal honours the request. The Linux console and the DEC-era
## and "dumb" terminal types ignore DECSCUSR (or print it), and plain GNU
## `screen` swallows it. For those, `caretSupportFor` answers `caretDrawn` and the
## caret is DRAWN instead, into the cell it covers (`drawCaret`): reverse video
## for a block, underline for a bar or an underline — the cell keeps its glyph,
## so the character under the caret stays readable.
##
## Three things, all pure:
##
## * `caretSupportFor(term, termProgram)` — whether shapes are honoured,
##   decided from the terminal's own identity (`TERM`, `TERM_PROGRAM`);
## * `caretBytes(caret, support)` — the bytes that put the terminal's cursor
##   at the caret, in its shape, and show it (empty when it must be drawn);
## * `drawCaret(cell, shape)` — the fallback, on one composited cell.
##
## Positions are 0-based cells, as everywhere in this library; the bytes are
## 1-based, as the terminal wants them.

import std/strutils

import ./cells

type
  CaretShape* = enum
    ckBar = "bar"             ## inserting: a thin bar before the character
    ckBlock = "block"         ## overwriting: a block over the character
    ckUnderline = "underline"

  CaretSupport* = enum
    caretShapes = "shapes"
      ## The terminal moves and shows its cursor and honours DECSCUSR.
    caretDrawn = "none"
      ## The terminal is not known to honour DECSCUSR: draw the caret.

  TextCaret* = object
    ## A caret to show: its cell and its shape. `visible: false` hides the
    ## terminal's cursor (no field has focus).
    row*, col*: int
    shape*: CaretShape
    visible*: bool

const
  NoShapeTerms* = ["linux", "dumb", "vt52", "vt100", "vt102", "vt220",
                   "vt320", "ansi", "cons25", "screen", "sun", "wy50"]
    ## `TERM` values (or prefixes before a `-`) whose terminals do not honour
    ## DECSCUSR. `screen` is GNU screen, which drops the sequence; tmux
    ## advertises itself as `tmux-*` (or `screen-*` with `TMUX` set, see
    ## `caretSupportFor`) and passes it on.

func decscusrParam*(shape: CaretShape): int =
  ## DECSCUSR's steady variant of each shape.
  case shape
  of ckBlock: 2
  of ckUnderline: 4
  of ckBar: 6

func caretSupportFor*(term, termProgram: string; inTmux = false): CaretSupport =
  ## Whether a terminal identified by `TERM` / `TERM_PROGRAM` honours caret
  ## shapes. A known terminal program (`TERM_PROGRAM` set: iTerm2, WezTerm,
  ## Apple Terminal, vscode, …) always does; inside tmux (`inTmux`) the
  ## sequence is passed through, whatever `TERM` says; otherwise the `TERM`
  ## family decides, and an EMPTY `TERM` is treated as unknown — drawn.
  if termProgram.strip.len > 0 or inTmux:
    return caretShapes
  let t = term.strip.toLowerAscii
  if t.len == 0:
    return caretDrawn
  let family = t.split('-')[0]
  for bad in NoShapeTerms:
    if family == bad:
      return caretDrawn
  caretShapes

func caretBytes*(caret: TextCaret; support: CaretSupport): string =
  ## The bytes that show `caret` with the terminal's own cursor: the shape
  ## (DECSCUSR), the position (CUP, 1-based) and DECTCEM show — or, for a
  ## hidden caret, DECTCEM hide alone. With `caretDrawn` the terminal's cursor is
  ## hidden and the caller draws the caret (`drawCaret`).
  if not caret.visible or support == caretDrawn:
    return "\x1b[?25l"
  "\x1b[" & $decscusrParam(caret.shape) & " q" &
    "\x1b[" & $(caret.row + 1) & ";" & $(caret.col + 1) & "H" &
    "\x1b[?25h"

func caretRestoreBytes*(): string =
  ## Hand the cursor's shape back to the user's default (DECSCUSR 0) — what
  ## an application writes when it leaves.
  "\x1b[0 q"

proc drawCaret*(cell: var Cell; shape: CaretShape) =
  ## The FALLBACK caret, drawn into the cell it covers: a block reverses the
  ## cell, a bar or an underline underlines it. The glyph is kept.
  case shape
  of ckBlock: cell.attrs.incl attrReverse
  of ckBar, ckUnderline: cell.attrs.incl attrUnderline
