## CellMap snapshot encoder — JSON, one entry per cell.
##
## Each cell is emitted as a small JSON object with `rune`, `fg`, `bg`,
## `attrs`, and `nodeId` (always 0 in M2; the node-id projection lands
## once layout is per-node in M3+). Output is deterministic across runs:
## key order is fixed, no whitespace beyond the structural spacing the
## reader expects.

import std/[unicode, strutils]

import ../../cells

proc colorJson(c: Color): string =
  case c.kind
  of ckDefault: "\"default\""
  of ckAnsi: "\"ansi:" & $ord(c.ansi) & "\""
  of ckIndexed: "\"idx:" & $c.indexed & "\""
  of ckRgb: "\"rgb:" & $c.r & "," & $c.g & "," & $c.b & "\""

proc attrsJson(s: set[Attr]): string =
  var parts: seq[string] = @[]
  for a in s:
    parts.add "\"" & $a & "\""
  "[" & parts.join(",") & "]"

proc encodeCellMap*(buf: ScreenBuffer): string =
  var lines: seq[string] = @[]
  lines.add "{"
  lines.add "  \"cols\": " & $buf.cols & ","
  lines.add "  \"rows\": " & $buf.rowsCount & ","
  lines.add "  \"cells\": ["
  var rowParts: seq[string] = @[]
  for r in 0 ..< buf.rowsCount:
    var cellParts: seq[string] = @[]
    for c in 0 ..< buf.cols:
      let cell = buf[r, c]
      let runeStr =
        if cell.rune.int32 == 0: " "
        else: $cell.rune
      let parts = @[
        "\"rune\":\"" & runeStr.replace("\\", "\\\\").replace("\"", "\\\"") & "\"",
        "\"fg\":" & colorJson(cell.fg),
        "\"bg\":" & colorJson(cell.bg),
        "\"attrs\":" & attrsJson(cell.attrs),
        "\"width\":" & $cell.width.int,
        "\"nodeId\":0"
      ]
      cellParts.add "{" & parts.join(",") & "}"
    rowParts.add "    [" & cellParts.join(",") & "]"
  lines.add rowParts.join(",\n")
  lines.add "  ]"
  lines.add "}"
  result = lines.join("\n") & "\n"
