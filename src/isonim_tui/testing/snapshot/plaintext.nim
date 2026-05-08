## Plain-text snapshot encoder.
##
## Produces a row-major dump of the screen buffer's runes. No styling,
## no escape sequences. The simplest possible diff format — `git diff`
## reads it directly.

import std/[unicode, strutils]
import ../../cells

proc encodePlaintext*(buf: ScreenBuffer): string =
  ## One line per row, terminated by a single '\n'. Width-2 cells emit
  ## the wide rune; their ghost trailing-half cell is skipped.
  var lines: seq[string] = @[]
  for r in 0 ..< buf.rowsCount:
    var line = ""
    for c in 0 ..< buf.cols:
      let cell = buf[r, c]
      if cell.width == 0: continue
      if cell.rune.int32 == 0:
        line.add ' '
      else:
        line.add $cell.rune
    # Trim trailing whitespace so cosmetic blanks don't bloat the
    # snapshot. Tests can still detect content differences exactly.
    lines.add line.strip(leading = false, trailing = true)
  result = lines.join("\n") & "\n"
