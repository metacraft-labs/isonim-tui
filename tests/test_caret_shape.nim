## test_caret_shape
##
## The caret of a text field: the terminal's own cursor, placed where the text
## goes, a thin bar while inserting and a block while overwriting (DECSCUSR) —
## and, on a terminal that is not known to honour DECSCUSR, a caret DRAWN into
## the cell it covers instead.
##
## No mocks: the fallback draws into a cell composited by the production
## renderer and compositor (`newTerminalTestHarness`); the bytes and the
## terminal table are pure functions, asserted as values.

import std/[unicode, unittest]

import isonim_tui

suite "caret shapes":
  test "insert is a steady bar, overwrite a steady block, at a 1-based CUP":
    let insert = TextCaret(row: 0, col: 17, shape: ckBar, visible: true)
    check caretBytes(insert, caretShapes) == "\x1b[6 q\x1b[1;18H\x1b[?25h"
    let over = TextCaret(row: 4, col: 2, shape: ckBlock, visible: true)
    check caretBytes(over, caretShapes) == "\x1b[2 q\x1b[5;3H\x1b[?25h"
    check decscusrParam(ckUnderline) == 4
    # A hidden caret hides the cursor and sets no shape.
    check caretBytes(TextCaret(visible: false, shape: ckBar), caretShapes) ==
      "\x1b[?25l"
    check caretRestoreBytes() == "\x1b[0 q"

  test "which terminals honour DECSCUSR":
    check caretSupportFor("xterm-256color", "") == caretShapes
    check caretSupportFor("tmux-256color", "") == caretShapes
    check caretSupportFor("xterm-kitty", "") == caretShapes
    check caretSupportFor("alacritty", "") == caretShapes
    # The Linux console, DEC and dumb types, plain GNU screen: drawn.
    check caretSupportFor("linux", "") == caretDrawn
    check caretSupportFor("dumb", "") == caretDrawn
    check caretSupportFor("vt100", "") == caretDrawn
    check caretSupportFor("screen", "") == caretDrawn
    check caretSupportFor("screen-256color", "") == caretDrawn
    check caretSupportFor("", "") == caretDrawn
    # …but tmux passes it through whatever TERM says, and a terminal that
    # names itself does.
    check caretSupportFor("screen-256color", "", inTmux = true) == caretShapes
    check caretSupportFor("", "WezTerm") == caretShapes
    # Where the caret is drawn, the terminal's cursor is hidden.
    check caretBytes(TextCaret(row: 0, col: 1, shape: ckBar, visible: true),
                     caretDrawn) == "\x1b[?25l"

  test "the fallback caret keeps the glyph: block reverses, bar underlines":
    let h = newTerminalTestHarness(8, 1)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.appendChild(root, r.createTextNode("query"))
      root)
    let cell = h.cellAt(0, 2)
    check $cell.rune == "e"
    var blockCell = cell
    drawCaret(blockCell, ckBlock)
    check attrReverse in blockCell.attrs
    check $blockCell.rune == "e"
    check blockCell.fg == cell.fg and blockCell.bg == cell.bg
    var bar = cell
    drawCaret(bar, ckBar)
    check attrUnderline in bar.attrs
    check attrReverse notin bar.attrs
    check $bar.rune == "e"
    h.dispose()
