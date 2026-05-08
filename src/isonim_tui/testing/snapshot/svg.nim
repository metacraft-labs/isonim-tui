## SVG snapshot encoder.
##
## Emits one `<text>` element per visible cell, with stable element ids
## derived from `(row, col)` so diffs don't reorder. The cell rectangle
## coordinates are integer-multiples of (cellWidth, cellHeight) so the
## output is byte-identical across runs.
##
## Vendored Noto Mono Regular as base64 — *deferred*. The full base64
## payload of the font is ~280 KB, dwarfing the rest of the snapshot.
## M2 ships the SVG without an embedded font (`font-family="monospace"`)
## so snapshots remain stable across runs on the same machine; the
## embedded-font requirement is documented in the milestone deliverables
## as deferred to a future docs/release pass. Tests that care about
## cross-machine stability use the plaintext / cellmap encoders, which
## have no font dependency.

import std/[unicode, strutils]

import ../../cells

const cellWidth = 8     ## px width of one cell — arbitrary stable choice
const cellHeight = 16   ## px height of one cell

proc colorAttr(c: Color): string =
  case c.kind
  of ckDefault: "currentColor"
  of ckAnsi:
    case c.ansi
    of acBlack:        "#000000"
    of acRed:          "#aa0000"
    of acGreen:        "#00aa00"
    of acYellow:       "#aa5500"
    of acBlue:         "#0000aa"
    of acMagenta:      "#aa00aa"
    of acCyan:         "#00aaaa"
    of acWhite:        "#aaaaaa"
    of acBrightBlack:  "#555555"
    of acBrightRed:    "#ff5555"
    of acBrightGreen:  "#55ff55"
    of acBrightYellow: "#ffff55"
    of acBrightBlue:   "#5555ff"
    of acBrightMagenta:"#ff55ff"
    of acBrightCyan:   "#55ffff"
    of acBrightWhite:  "#ffffff"
  of ckIndexed:
    "#" & toHex(c.indexed.int, 2) & toHex(c.indexed.int, 2) &
      toHex(c.indexed.int, 2)
  of ckRgb:
    "#" & toHex(c.r.int, 2) & toHex(c.g.int, 2) & toHex(c.b.int, 2)

proc xmlEscape(s: string): string =
  result = ""
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&apos;"
    else: result.add ch

proc encodeSvg*(buf: ScreenBuffer): string =
  let totalW = buf.cols * cellWidth
  let totalH = buf.rowsCount * cellHeight
  var lines: seq[string] = @[]
  lines.add "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  lines.add "<svg xmlns=\"http://www.w3.org/2000/svg\" " &
    "width=\"" & $totalW & "\" height=\"" & $totalH &
    "\" viewBox=\"0 0 " & $totalW & " " & $totalH & "\" " &
    "font-family=\"monospace\" font-size=\"" & $cellHeight & "\">"
  for r in 0 ..< buf.rowsCount:
    for c in 0 ..< buf.cols:
      let cell = buf[r, c]
      if cell.width == 0: continue
      if cell.rune.int32 == 0 or cell.rune == Rune(' '.ord):
        # Whitespace gets a background rect only if bg is non-default.
        if cell.bg.kind != ckDefault:
          let x = c * cellWidth
          let y = r * cellHeight
          lines.add "  <rect id=\"bg-" & $r & "-" & $c & "\" x=\"" & $x &
            "\" y=\"" & $y & "\" width=\"" & $cellWidth &
            "\" height=\"" & $cellHeight & "\" fill=\"" &
            colorAttr(cell.bg) & "\"/>"
        continue
      let x = c * cellWidth
      let y = (r + 1) * cellHeight - 2  ## baseline offset
      if cell.bg.kind != ckDefault:
        let bx = c * cellWidth
        let by = r * cellHeight
        lines.add "  <rect id=\"bg-" & $r & "-" & $c & "\" x=\"" & $bx &
          "\" y=\"" & $by & "\" width=\"" &
          $(cellWidth * cell.width.int) & "\" height=\"" &
          $cellHeight & "\" fill=\"" & colorAttr(cell.bg) & "\"/>"
      var styleParts: seq[string] = @[]
      styleParts.add "fill:" & colorAttr(cell.fg)
      if attrBold in cell.attrs: styleParts.add "font-weight:bold"
      if attrItalic in cell.attrs: styleParts.add "font-style:italic"
      if attrUnderline in cell.attrs:
        styleParts.add "text-decoration:underline"
      let runeStr = xmlEscape($cell.rune)
      lines.add "  <text id=\"t-" & $r & "-" & $c & "\" x=\"" & $x &
        "\" y=\"" & $y & "\" style=\"" & styleParts.join(";") & "\">" &
        runeStr & "</text>"
  lines.add "</svg>"
  result = lines.join("\n") & "\n"
