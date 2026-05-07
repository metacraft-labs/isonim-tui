## SGR (Select Graphic Rendition) encoder + cursor / screen-mode escapes.
##
## Produces minimal ANSI byte sequences for transitioning a terminal
## from one (foreground, background, attribute-set) tuple to another.
## "Minimal" means: no SGR is emitted for fields that didn't change.
## "Reset" is only emitted when an attribute that was on must be turned
## off and there is no targeted SGR for that disable.
##
## All public APIs are pure functions over value types defined in
## `isonim_tui/cells.nim` (`Color`, `Attr`). No mutable state. Charter
## §1: value types only; output is a `string` so the caller controls
## allocation.

import std/[strutils]

import ../cells

# ----------------------------------------------------------------------------
# Style — a paired (fg, bg, attrs) snapshot.
# ----------------------------------------------------------------------------

type
  Style* = object
    ## A render-style snapshot consisting of foreground colour,
    ## background colour, and the active attribute flag set. The SGR
    ## encoder takes a "previous" Style and a "current" Style and emits
    ## the minimal escape sequence to transition between them.
    fg*: Color
    bg*: Color
    attrs*: set[Attr]

proc newStyle*(fg: Color = defaultColor(); bg: Color = defaultColor();
               attrs: set[Attr] = {}): Style {.inline.} =
  Style(fg: fg, bg: bg, attrs: attrs)

proc defaultStyle*(): Style {.inline.} = Style(
  fg: defaultColor(), bg: defaultColor(), attrs: {})

proc `==`*(a, b: Style): bool {.inline.} =
  a.fg == b.fg and a.bg == b.bg and a.attrs == b.attrs

# ----------------------------------------------------------------------------
# Attribute → SGR-on / SGR-off codes
# ----------------------------------------------------------------------------

proc attrOnCode(a: Attr): int {.inline.} =
  case a
  of attrBold:      1
  of attrDim:       2
  of attrItalic:    3
  of attrUnderline: 4
  of attrBlink:     5
  of attrReverse:   7
  of attrInvisible: 8
  of attrStrike:    9

proc attrOffCode(a: Attr): int {.inline.} =
  case a
  of attrBold, attrDim:  22  ## bold/dim share an off-code
  of attrItalic:         23
  of attrUnderline:      24
  of attrBlink:          25
  of attrReverse:        27
  of attrInvisible:      28
  of attrStrike:         29

# ----------------------------------------------------------------------------
# Colour → SGR parameters
# ----------------------------------------------------------------------------

proc fgParams(c: Color): string =
  case c.kind
  of ckDefault: "39"
  of ckAnsi:
    let n = ord(c.ansi)
    if n < 8: $(30 + n) else: $(90 + (n - 8))
  of ckIndexed: "38;5;" & $c.indexed
  of ckRgb:     "38;2;" & $c.r & ";" & $c.g & ";" & $c.b

proc bgParams(c: Color): string =
  case c.kind
  of ckDefault: "49"
  of ckAnsi:
    let n = ord(c.ansi)
    if n < 8: $(40 + n) else: $(100 + (n - 8))
  of ckIndexed: "48;5;" & $c.indexed
  of ckRgb:     "48;2;" & $c.r & ";" & $c.g & ";" & $c.b

# ----------------------------------------------------------------------------
# SGR transition encoder
# ----------------------------------------------------------------------------

proc renderSgr*(prev, curr: Style): string =
  ## Emit the minimal SGR escape sequence that turns terminal state from
  ## `prev` into `curr`.
  ##
  ## Behaviour:
  ##   * If only fg changed, emits the fg SGR.
  ##   * If only attributes were *added*, emits each add code.
  ##   * If attributes were *removed*, prefers the targeted off-code
  ##     (e.g. `\e[24m` for underline-off) over a full `\e[0m` reset.
  ##   * `\e[0m` reset is only emitted when removing bold/dim simultaneously
  ##     would not work cleanly (handled implicitly by the targeted codes
  ##     so `reset` is rarely emitted from this function).
  ##   * Returns "" when prev == curr.
  if prev == curr: return ""
  var params: seq[string] = @[]
  # Attributes removed (in prev, not in curr)
  let removed = prev.attrs - curr.attrs
  for a in removed:
    params.add($attrOffCode(a))
  # Attributes added (in curr, not in prev)
  let added = curr.attrs - prev.attrs
  for a in added:
    params.add($attrOnCode(a))
  if curr.fg != prev.fg:
    params.add(fgParams(curr.fg))
  if curr.bg != prev.bg:
    params.add(bgParams(curr.bg))
  if params.len == 0: return ""
  return "\x1b[" & params.join(";") & "m"

proc reset*(): string {.inline.} =
  ## Hard reset to terminal defaults.
  "\x1b[0m"

# ----------------------------------------------------------------------------
# Convenience colour constructors mirroring the Textual API.
# ----------------------------------------------------------------------------

type ColorBuilder* = object  ## Phantom type for `ColorB.rgb(...)` style.

const colorB* = ColorBuilder()

proc rgb*(_: ColorBuilder; r, g, b: uint8): Color {.inline.} =
  rgbColor(r, g, b)

proc indexed*(_: ColorBuilder; idx: uint8): Color {.inline.} =
  indexedColor(idx)

proc ansi*(_: ColorBuilder; c: AnsiColor): Color {.inline.} =
  ansiColor(c)

# ----------------------------------------------------------------------------
# Cursor + screen-mode escape sequences.
# ----------------------------------------------------------------------------

proc cursorTo*(row, col: int): string {.inline.} =
  ## Move cursor to (row, col) in 1-based screen coordinates. Inputs are
  ## 0-based for ergonomic parity with the Cell grid; we add 1 here.
  "\x1b[" & $(row + 1) & ";" & $(col + 1) & "H"

proc cursorUp*(n: int = 1): string {.inline.} = "\x1b[" & $n & "A"
proc cursorDown*(n: int = 1): string {.inline.} = "\x1b[" & $n & "B"
proc cursorForward*(n: int = 1): string {.inline.} = "\x1b[" & $n & "C"
proc cursorBack*(n: int = 1): string {.inline.} = "\x1b[" & $n & "D"

proc cursorSave*(): string {.inline.} = "\x1b[s"
proc cursorRestore*(): string {.inline.} = "\x1b[u"
proc cursorHide*(): string {.inline.} = "\x1b[?25l"
proc cursorShow*(): string {.inline.} = "\x1b[?25h"

proc clearScreen*(): string {.inline.} = "\x1b[2J"
proc clearLine*(): string {.inline.} = "\x1b[2K"
proc enableAltScreen*(): string {.inline.} = "\x1b[?1049h"
proc disableAltScreen*(): string {.inline.} = "\x1b[?1049l"

# ----------------------------------------------------------------------------
# Named-colour palette helpers (a small subset of CSS / X11 names).
# ----------------------------------------------------------------------------

const namedColors*: array[16, tuple[name: string; ansi: AnsiColor]] = [
  ("black", acBlack),
  ("red", acRed),
  ("green", acGreen),
  ("yellow", acYellow),
  ("blue", acBlue),
  ("magenta", acMagenta),
  ("cyan", acCyan),
  ("white", acWhite),
  ("bright_black", acBrightBlack),
  ("bright_red", acBrightRed),
  ("bright_green", acBrightGreen),
  ("bright_yellow", acBrightYellow),
  ("bright_blue", acBrightBlue),
  ("bright_magenta", acBrightMagenta),
  ("bright_cyan", acBrightCyan),
  ("bright_white", acBrightWhite)
]

proc namedColor*(name: string): Color =
  ## Parse one of the 16 standard ANSI palette names. Returns
  ## `defaultColor()` when not found (so callers can pipe through
  ## without checking — width-style style strings degrade gracefully).
  for entry in namedColors:
    if entry.name == name: return ansiColor(entry.ansi)
  return defaultColor()
