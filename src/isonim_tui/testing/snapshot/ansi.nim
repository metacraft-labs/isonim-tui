## ANSI snapshot encoder — replayable byte stream.
##
## Walks the buffer cell-by-cell and emits the same SGR-aware byte
## stream a real driver would have written. `cat` will replay it on a
## terminal.

import std/[unicode]

import ../../cells
import ../../text/ansi as ansiMod

proc encodeAnsi*(buf: ScreenBuffer): string =
  var s = ""
  var prev = defaultStyle()
  for r in 0 ..< buf.rowsCount:
    if r > 0: s.add '\n'
    for c in 0 ..< buf.cols:
      let cell = buf[r, c]
      if cell.width == 0: continue
      let curr = newStyle(cell.fg, cell.bg, cell.attrs)
      let trans = renderSgr(prev, curr)
      if trans.len > 0:
        s.add trans
        prev = curr
      if cell.rune.int32 == 0:
        s.add ' '
      else:
        s.add $cell.rune
  s.add ansiMod.reset()
  s.add '\n'
  s
