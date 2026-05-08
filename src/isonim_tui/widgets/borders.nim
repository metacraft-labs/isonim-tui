## widgets/borders.nim — box-drawing glyph tables shared across widgets.
##
## Mirrors Textual's `_border.py` mapping from `BorderStyle` (`solid`,
## `round`, `double`, `heavy`, `ascii`, …) to its corresponding Unicode
## (or ASCII) box-drawing characters. Every widget that paints a
## border (Static, Container, Rule, Placeholder when `:layout-debug`)
## reaches into this module — the canonical mapping lives here so a
## change picks up across the widget set.
##
## *Charter §1*: every type is a value `object`. The glyph table is a
## value record returned by lookup; nothing is mutable.

import ../css/properties
import ../text/width as widthMod

type
  BorderGlyphs* = object
    ## The six characters needed to draw a rectangular border. The
    ## "horizontal" / "vertical" glyphs repeat to fill the runs; the
    ## four corners go in the obvious slots.
    ##
    ## All fields are *strings* rather than `Rune` because some border
    ## styles use multi-byte UTF-8 sequences and the widgets emit text
    ## by simple string concatenation.
    topLeft*: string
    topRight*: string
    bottomLeft*: string
    bottomRight*: string
    horizontal*: string
    vertical*: string
    left*: string                  ## Convenience: same as `vertical & " "`
                                   ## prefix? No — `left` is the left edge
                                   ## glyph drawn at the start of an
                                   ## interior row.
    right*: string

proc bordersGlyphs*(style: BorderStyle): BorderGlyphs =
  ## Look up the glyph set for the given `BorderStyle`. Falls back to
  ## the ASCII set for unknown / `bsNone` so callers always get a
  ## non-empty result they can concatenate.
  case style
  of bsNone, bsHidden, bsBlank:
    BorderGlyphs(
      topLeft: " ", topRight: " ", bottomLeft: " ", bottomRight: " ",
      horizontal: " ", vertical: " ", left: " ", right: " ")
  of bsAscii:
    BorderGlyphs(
      topLeft: "+", topRight: "+", bottomLeft: "+", bottomRight: "+",
      horizontal: "-", vertical: "|", left: "|", right: "|")
  of bsRound:
    BorderGlyphs(
      topLeft: "╭", topRight: "╮",
      bottomLeft: "╰", bottomRight: "╯",
      horizontal: "─", vertical: "│",
      left: "│", right: "│")
  of bsSolid, bsInner, bsOuter, bsTall, bsPanel, bsTab, bsWide:
    BorderGlyphs(
      topLeft: "┌", topRight: "┐",
      bottomLeft: "└", bottomRight: "┘",
      horizontal: "─", vertical: "│",
      left: "│", right: "│")
  of bsDouble:
    BorderGlyphs(
      topLeft: "╔", topRight: "╗",
      bottomLeft: "╚", bottomRight: "╝",
      horizontal: "═", vertical: "║",
      left: "║", right: "║")
  of bsDashed:
    BorderGlyphs(
      topLeft: "┌", topRight: "┐",
      bottomLeft: "└", bottomRight: "┘",
      horizontal: "┄", vertical: "┆",
      left: "┆", right: "┆")
  of bsHeavy, bsThick, bsBlock:
    BorderGlyphs(
      topLeft: "┏", topRight: "┓",
      bottomLeft: "┗", bottomRight: "┛",
      horizontal: "━", vertical: "┃",
      left: "┃", right: "┃")
  of bsHkey:
    BorderGlyphs(
      topLeft: "━", topRight: "━",
      bottomLeft: "━", bottomRight: "━",
      horizontal: "━", vertical: " ",
      left: " ", right: " ")
  of bsVkey:
    BorderGlyphs(
      topLeft: "┃", topRight: "┃",
      bottomLeft: "┃", bottomRight: "┃",
      horizontal: " ", vertical: "┃",
      left: "┃", right: "┃")

# ----------------------------------------------------------------------------
# Row builders — used by every bordered widget.
# ----------------------------------------------------------------------------

proc topBorderRow*(g: BorderGlyphs; innerWidth: int): string =
  ## Build the top row: top-left corner + horizontal*innerWidth +
  ## top-right corner.
  result = g.topLeft
  for _ in 0 ..< innerWidth:
    result.add g.horizontal
  result.add g.topRight

proc bottomBorderRow*(g: BorderGlyphs; innerWidth: int): string =
  result = g.bottomLeft
  for _ in 0 ..< innerWidth:
    result.add g.horizontal
  result.add g.bottomRight

# ----------------------------------------------------------------------------
# Cell-aware text helpers — every widget pads / truncates by *cells*,
# not by string length, so double-width glyphs and emoji align.
# ----------------------------------------------------------------------------

proc spaces*(n: int): string =
  ## `n` ASCII spaces. The compositor renders these as blank cells.
  if n <= 0: return ""
  result = newString(n)
  for i in 0 ..< n:
    result[i] = ' '

proc padOrTruncate*(text: string; cells: int): string =
  ## Cell-aware pad/truncate: returns a string whose `displayWidth`
  ## equals `cells`. Wide graphemes are not split — when the next
  ## cluster would overflow, we stop and pad the tail with spaces.
  if cells <= 0: return ""
  var built = ""
  var used = 0
  for cluster in graphemeClusters(text):
    let w = clusterDisplayWidth(cluster.text)
    if used + w > cells: break
    built.add cluster.text
    used += w
  if used < cells:
    built.add spaces(cells - used)
  built

proc cellWidth*(text: string): int {.inline.} =
  ## Display width of `text` in cells, grapheme-aware.
  widthMod.displayWidth(text)
