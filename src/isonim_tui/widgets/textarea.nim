## widgets/textarea.nim — Tier-3c `TextArea` widget (M19).
##
## Port of `textual/widgets/_text_area.py` + `textual/widgets/text_area.py`
## (~2,661 LOC combined) — pragmatic core. The most architecturally
## complex widget. Ships:
##
##   * Multi-line editing over **grapheme clusters** (M1's iterator) —
##     never bytes — so `Backspace` deletes one user-perceived glyph (a
##     ZWJ family is one cluster), not one UTF-8 byte.
##   * Cursor + selection state machine over (line, column) coordinates
##     where `column` is a cluster index inside the line.
##   * Word-wrap (soft-wrap) display rows with grapheme-aware breaks —
##     never splits a cluster.
##   * Undo/redo with a snapshot stack (cursor + selection restored at
##     each step). `Ctrl+Z` / `Ctrl+Y`.
##   * Word boundaries: `Ctrl+Left` / `Ctrl+Right` for word-by-word
##     navigation; `Ctrl+W` / `Ctrl+Delete` for word-deletion.
##   * Soft tabs: pressing `Tab` inserts `tabSize` spaces; pressing
##     `Shift+Tab` dedents the current line / selected lines by up to
##     `tabSize` leading spaces.
##   * Indent / dedent of selected line range via `Tab` / `Shift+Tab`
##     when the selection spans multiple lines.
##   * Syntax-highlighting **interface** with a stub implementation.
##     Tree-sitter integration is deferred — the FFI to the C library +
##     grammar bundling is out of scope for M19's pragmatic core. The
##     widget exposes a `setHighlighter` hook so M20 (Markdown) and
##     later milestones can plug a real engine in without touching
##     the editing core.
##
## Default keybindings (mirrors `_text_area.py`'s BINDINGS):
##   * `Left` / `Right`             — cursor by one grapheme cluster
##   * `Up` / `Down`                — cursor by one display row
##   * `Shift+Left` / `Shift+Right` — extend selection by one cluster
##   * `Shift+Up` / `Shift+Down`    — extend selection by one row
##   * `Home` / `Ctrl+A`            — go to line start (or document start)
##   * `End`  / `Ctrl+E`            — go to line end (or document end)
##   * `Ctrl+Home`                  — document start
##   * `Ctrl+End`                   — document end
##   * `Ctrl+Left` / `Ctrl+Right`   — word-by-word navigation
##   * `Backspace`                  — delete cluster left (or selection)
##   * `Delete`                     — delete cluster right (or selection)
##   * `Ctrl+W`                     — delete word left
##   * `Enter`                      — split line at cursor
##   * `Tab`                        — indent (selection or insert spaces)
##   * `Shift+Tab`                  — dedent
##   * `Ctrl+Z`                     — undo
##   * `Ctrl+Y` / `Ctrl+Shift+Z`    — redo
##   * any printable character      — insert (replaces selection if any)
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import std/[strutils, unicode]

import ../renderer
import ../events
import ../css/properties
import ../text/width as widthMod
import ./borders

# ----------------------------------------------------------------------------
# Public types — coordinates, document, selection, undo state.
# ----------------------------------------------------------------------------

type
  Caret* = object
    ## A position inside the document. `line` is a 0-based line index;
    ## `column` is a grapheme-cluster index inside that line (0 means
    ## "before the first cluster", N means "after the last cluster").
    line*: int
    column*: int

  TextSelection* = object
    ## Half-open selection over (line, column) coordinates. When
    ## `anchor == cursor`, the selection is empty and only the cursor is
    ## visible. The pair is normalised so `selStart`/`selEnd` return them
    ## in document order regardless of the user's drag direction.
    anchor*: Caret
    cursor*: Caret

  HighlightKind* = enum
    ## Categories of syntactic highlight. Tree-sitter grammars surface
    ## many more (function names, types, constants…), but the editor
    ## only needs a small fixed palette to colour cells. The categories
    ## mirror what M5's CSS `.token-*` selectors paint.
    hkPlain
    hkKeyword
    hkString
    hkNumber
    hkComment
    hkOperator
    hkType
    hkFunction

  Highlight* = object
    ## A coloured run inside a logical line. `startCluster` and
    ## `endCluster` are cluster indices into the line; `endCluster` is
    ## exclusive. `kind` selects the colour from the palette.
    startCluster*: int
    endCluster*: int
    kind*: HighlightKind

  HighlighterProc* = proc(line: string; lineIndex: int): seq[Highlight] {.closure.}
    ## Plug-point for syntax highlighting. Receives a single logical
    ## line (no embedded `\n`) plus its line index; returns the spans
    ## that should be coloured. Tree-sitter integration (deferred) is
    ## one possible implementation; the simple Python keyword stub
    ## installed via `setLanguage("python")` is another. Returning an
    ## empty seq means "no highlights for this line".

  EditOp* = enum
    ## Discriminator for the undo stack. The stack stores deltas, not
    ## full snapshots, so memory grows linearly with edits rather than
    ## with `lines * edits`.
    eoInsert
    eoDelete
    eoSplitLine
    eoJoinLines
    eoReplace

  EditDelta* = object
    ## One reversible edit. `before` / `after` carry the document
    ## state needed to apply or undo. The cursor + selection at the
    ## time of the edit are also recorded so undo restores them.
    case op*: EditOp
    of eoInsert, eoDelete:
      pos*: Caret
      text*: string             ## What was inserted (eoInsert) or
                                ## removed (eoDelete).
    of eoSplitLine:
      splitAt*: Caret
    of eoJoinLines:
      joinAt*: int              ## Line index N — joins line N and N+1.
                                ## Length of the original line N (in
                                ## bytes) is needed to undo.
      origLineLen*: int
    of eoReplace:
      replaceStart*: Caret
      replaceEnd*: Caret
      removed*: string
      inserted*: string
    cursorBefore*: Caret
    anchorBefore*: Caret
    cursorAfter*: Caret
    anchorAfter*: Caret

  TextAreaWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    lines*: seq[string]                 ## One entry per logical line.
                                        ## Each holds raw UTF-8 bytes
                                        ## without any embedded `\n`.
    selection*: TextSelection
    width*: int                         ## Inner width in cells.
    viewportHeight*: int                ## Number of display rows
                                        ## visible at once.
    scrollY*: int                       ## Top display-row in view.
    border*: BorderStyle
    borderColor*: string
    color*: string
    tabSize*: int                       ## Spaces per soft-tab.
    softWrap*: bool                     ## When true, long lines wrap
                                        ## across display rows.
    readOnly*: bool
    disabled*: bool
    language*: string                   ## Informational; selects which
                                        ## stub highlighter activates.
    highlighter*: HighlighterProc
    onChange*: proc(newDoc: string)
    undoStack*: seq[EditDelta]
    redoStack*: seq[EditDelta]
    maxUndoDepth*: int                  ## 0 = unlimited.

# Forward declarations
proc renderTree*(t: TextAreaWidget)
proc text*(t: TextAreaWidget): string
proc setText*(t: TextAreaWidget; doc: string)
proc moveCursorTo*(t: TextAreaWidget; pos: Caret; selecting: bool = false)
proc insertText*(t: TextAreaWidget; s: string)
proc deleteSelection*(t: TextAreaWidget): bool {.discardable.}
proc backspace*(t: TextAreaWidget)
proc deleteRight*(t: TextAreaWidget)
proc splitLine*(t: TextAreaWidget)
proc undo*(t: TextAreaWidget): bool {.discardable.}
proc redo*(t: TextAreaWidget): bool {.discardable.}
proc setLanguage*(t: TextAreaWidget; language: string)

# ----------------------------------------------------------------------------
# Cluster boundary helpers (per-line). Mirrors widgets/input.nim but in
# a multi-line context: every helper takes (or returns) (line, column).
# ----------------------------------------------------------------------------

proc clusterBoundaries(s: string): seq[int] =
  ## Byte boundaries for `s`. Length = clusterCount + 1.
  ## `result[0] == 0`; `result[^1] == s.len`.
  result = @[0]
  for c in graphemeClusters(s):
    result.add c.stop

proc clusterCount(s: string): int =
  result = 0
  for _ in graphemeClusters(s):
    inc result

proc clusterTextAt(s: string; idx: int): string =
  ## Substring of cluster index `idx`. Empty if out of range.
  var i = 0
  for c in graphemeClusters(s):
    if i == idx: return c.text
    inc i
  return ""

proc clamp(v, lo, hi: int): int {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

# ----------------------------------------------------------------------------
# Caret comparison + ordering.
# ----------------------------------------------------------------------------

proc `==`*(a, b: Caret): bool {.inline.} =
  a.line == b.line and a.column == b.column

proc `<`*(a, b: Caret): bool {.inline.} =
  if a.line != b.line: a.line < b.line
  else: a.column < b.column

proc `<=`*(a, b: Caret): bool {.inline.} =
  a == b or a < b

proc selStart*(t: TextAreaWidget): Caret {.inline.} =
  if t.selection.anchor <= t.selection.cursor: t.selection.anchor
  else: t.selection.cursor

proc selEnd*(t: TextAreaWidget): Caret {.inline.} =
  if t.selection.anchor <= t.selection.cursor: t.selection.cursor
  else: t.selection.anchor

proc hasSelection*(t: TextAreaWidget): bool {.inline.} =
  t.selection.anchor != t.selection.cursor

proc cursor*(t: TextAreaWidget): Caret {.inline.} =
  t.selection.cursor

proc lineCount*(t: TextAreaWidget): int {.inline.} =
  t.lines.len

proc lineLen*(t: TextAreaWidget; line: int): int {.inline.} =
  ## Cluster count of line `line` (0 if out of range).
  if line < 0 or line >= t.lines.len: 0
  else: clusterCount(t.lines[line])

proc clampCaret*(t: TextAreaWidget; pos: Caret): Caret =
  ## Project an arbitrary `Caret` onto a valid document position.
  ## When the line index is out-of-range we snap to the last line; when
  ## the column is past the line's cluster count we snap to the line's
  ## end. This is the canonical ground-truth for keyboard navigation.
  var line = clamp(pos.line, 0, max(0, t.lines.len - 1))
  if t.lines.len == 0:
    return Caret(line: 0, column: 0)
  let n = clusterCount(t.lines[line])
  let col = clamp(pos.column, 0, n)
  Caret(line: line, column: col)

# ----------------------------------------------------------------------------
# Document text accessors.
# ----------------------------------------------------------------------------

proc text*(t: TextAreaWidget): string =
  ## The full document as one string with `\n` separators between lines.
  result = ""
  for i, line in t.lines:
    if i > 0: result.add '\n'
    result.add line

# ----------------------------------------------------------------------------
# Default Python-keyword stub highlighter. Tree-sitter integration is
# deferred per M19 milestone scope; this lets us validate that the
# rendering pipeline picks up highlight runs without depending on the
# C grammar at build time.
# ----------------------------------------------------------------------------

const PythonKeywords = [
  "False", "None", "True", "and", "as", "assert", "async", "await",
  "break", "class", "continue", "def", "del", "elif", "else", "except",
  "finally", "for", "from", "global", "if", "import", "in", "is",
  "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
  "while", "with", "yield"
]

proc isWordChar(c: char): bool {.inline.} =
  c.isAlphaNumeric or c == '_'

proc pythonKeywordHighlighter*(line: string; lineIndex: int): seq[Highlight] =
  ## Stub Python highlighter used by `setLanguage("python")` until
  ## tree-sitter is wired in. Walks ASCII word boundaries, matches each
  ## word against `PythonKeywords`, and records a cluster-range
  ## `Highlight` per match. Cluster indices are computed by walking
  ## grapheme boundaries — keeps wide-glyph code lines (e.g. comments
  ## with emoji) correctly aligned.
  result = @[]
  if line.len == 0: return
  discard lineIndex
  # Build cluster index by byte offset.
  var bytePos = 0
  var clusterIdx = 0
  var byteToCluster = newSeq[int](line.len + 1)
  for c in graphemeClusters(line):
    while bytePos <= c.start:
      byteToCluster[bytePos] = clusterIdx
      inc bytePos
    inc clusterIdx
  while bytePos <= line.len:
    byteToCluster[bytePos] = clusterIdx
    inc bytePos
  # Scan word tokens by byte.
  var i = 0
  while i < line.len:
    if isWordChar(line[i]):
      let wstart = i
      while i < line.len and isWordChar(line[i]):
        inc i
      let word = line[wstart ..< i]
      var isKw = false
      for kw in PythonKeywords:
        if word == kw:
          isKw = true
          break
      if isKw:
        let startCl = byteToCluster[wstart]
        let endCl = byteToCluster[i]
        result.add Highlight(startCluster: startCl, endCluster: endCl,
                             kind: hkKeyword)
    else:
      inc i

proc nimKeywordHighlighter*(line: string; lineIndex: int): seq[Highlight] =
  ## Trivial Nim keyword highlighter. Symmetric with the Python stub —
  ## same shape, different keyword list.
  const NimKeywords = [
    "addr", "and", "as", "asm", "block", "break", "case", "cast",
    "concept", "const", "continue", "converter", "defer", "discard",
    "distinct", "div", "do", "elif", "else", "end", "enum", "except",
    "export", "finally", "for", "from", "func", "if", "import", "in",
    "include", "interface", "is", "isnot", "iterator", "let", "macro",
    "method", "mixin", "mod", "nil", "not", "notin", "object", "of",
    "or", "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr",
    "static", "template", "try", "tuple", "type", "using", "var",
    "when", "while", "xor", "yield"
  ]
  result = @[]
  if line.len == 0: return
  discard lineIndex
  var bytePos = 0
  var clusterIdx = 0
  var byteToCluster = newSeq[int](line.len + 1)
  for c in graphemeClusters(line):
    while bytePos <= c.start:
      byteToCluster[bytePos] = clusterIdx
      inc bytePos
    inc clusterIdx
  while bytePos <= line.len:
    byteToCluster[bytePos] = clusterIdx
    inc bytePos
  var i = 0
  while i < line.len:
    if isWordChar(line[i]):
      let wstart = i
      while i < line.len and isWordChar(line[i]):
        inc i
      let word = line[wstart ..< i]
      var isKw = false
      for kw in NimKeywords:
        if word == kw:
          isKw = true
          break
      if isKw:
        let startCl = byteToCluster[wstart]
        let endCl = byteToCluster[i]
        result.add Highlight(startCluster: startCl, endCluster: endCl,
                             kind: hkKeyword)
    else:
      inc i

# ----------------------------------------------------------------------------
# Display row mapping: each logical line, when soft-wrapped, occupies
# 1+ display rows. The vertical-arrow keys move by display rows.
# ----------------------------------------------------------------------------

type
  DisplayRow* = object
    ## A single display row produced by soft-wrap. `lineIndex` points
    ## back to the originating logical line. `startCluster` is the
    ## cluster offset within that line where this row starts;
    ## `endCluster` is exclusive.
    lineIndex*: int
    startCluster*: int
    endCluster*: int

proc wrapLineToRows(t: TextAreaWidget; line: string; lineIndex: int):
    seq[DisplayRow] =
  ## Soft-wrap one logical line into 1+ display rows. Wraps on cell
  ## width — never splits a grapheme cluster. When `softWrap` is off,
  ## emits a single `DisplayRow` covering all clusters (the renderer
  ## truncates at draw time).
  result = @[]
  let total = clusterCount(line)
  if total == 0:
    result.add DisplayRow(lineIndex: lineIndex, startCluster: 0,
                          endCluster: 0)
    return
  if not t.softWrap or t.width <= 0:
    result.add DisplayRow(lineIndex: lineIndex, startCluster: 0,
                          endCluster: total)
    return
  var startCl = 0
  var clIdx = 0
  var cells = 0
  for c in graphemeClusters(line):
    let w = clusterDisplayWidth(c.text)
    if w > t.width:
      # First cluster wider than viewport: emit it alone.
      if cells == 0:
        result.add DisplayRow(lineIndex: lineIndex, startCluster: clIdx,
                              endCluster: clIdx + 1)
        startCl = clIdx + 1
        cells = 0
      else:
        # Flush the current row, then emit the wide cluster alone.
        result.add DisplayRow(lineIndex: lineIndex, startCluster: startCl,
                              endCluster: clIdx)
        result.add DisplayRow(lineIndex: lineIndex, startCluster: clIdx,
                              endCluster: clIdx + 1)
        startCl = clIdx + 1
        cells = 0
    elif cells + w > t.width:
      result.add DisplayRow(lineIndex: lineIndex, startCluster: startCl,
                            endCluster: clIdx)
      startCl = clIdx
      cells = w
    else:
      cells += w
    inc clIdx
  if startCl < total:
    result.add DisplayRow(lineIndex: lineIndex, startCluster: startCl,
                          endCluster: total)
  if result.len == 0:
    result.add DisplayRow(lineIndex: lineIndex, startCluster: 0,
                          endCluster: total)

proc allDisplayRows*(t: TextAreaWidget): seq[DisplayRow] =
  ## Produce the complete sequence of display rows for the current
  ## document. Used by the renderer + by Up/Down arrow movement.
  result = @[]
  for i, line in t.lines:
    for row in wrapLineToRows(t, line, i):
      result.add row

proc displayRowOf*(t: TextAreaWidget; pos: Caret;
                   rows: seq[DisplayRow]): int =
  ## Return the index inside `rows` of the display row containing
  ## `pos`. Returns 0 when no row matches (shouldn't happen for a
  ## valid caret).
  for i, r in rows:
    if r.lineIndex == pos.line:
      if pos.column >= r.startCluster and pos.column <= r.endCluster:
        return i
  return 0

# ----------------------------------------------------------------------------
# Rendering — emits one box per display row plus optional border.
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc colorForKind*(kind: HighlightKind): string =
  ## Map a highlight kind to a CSS-friendly colour name. Tests assert
  ## the keyword colour matches `"syntax-keyword"`; the mapping is the
  ## minimal palette that exercises the renderer wiring.
  case kind
  of hkPlain:    ""
  of hkKeyword:  "syntax-keyword"
  of hkString:   "syntax-string"
  of hkNumber:   "syntax-number"
  of hkComment:  "syntax-comment"
  of hkOperator: "syntax-operator"
  of hkType:     "syntax-type"
  of hkFunction: "syntax-function"

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "";
             reverse: bool = false; dim: bool = false;
             bold: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  if dim:
    r.setStyle(box, "italic", "true")
  if bold:
    r.setStyle(box, "bold", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc emitHighlightedRow(r: TerminalRenderer; parent: TerminalNode;
                        segments: seq[tuple[text: string; color: string]];
                        leftEdge, rightEdge, edgeColor: string) =
  ## Emit a row whose body has multiple coloured segments. The renderer
  ## represents this as a parent `div` (one display row) with one child
  ## `div` per segment. The compositor's strip cache keys on the parent
  ## node id — segment changes invalidate the row, segment-static rows
  ## hit the cache.
  let row = r.createElement("div")
  if leftEdge.len > 0:
    let edgeBox = r.createElement("span")
    if edgeColor.len > 0:
      r.setStyle(edgeBox, "color", edgeColor)
    r.appendChild(edgeBox, r.createTextNode(leftEdge))
    r.appendChild(row, edgeBox)
  for seg in segments:
    if seg.text.len == 0: continue
    let segBox = r.createElement("span")
    if seg.color.len > 0:
      r.setStyle(segBox, "color", seg.color)
    r.appendChild(segBox, r.createTextNode(seg.text))
    r.appendChild(row, segBox)
  if rightEdge.len > 0:
    let edgeBox = r.createElement("span")
    if edgeColor.len > 0:
      r.setStyle(edgeBox, "color", edgeColor)
    r.appendChild(edgeBox, r.createTextNode(rightEdge))
    r.appendChild(row, edgeBox)
  r.appendChild(parent, row)

proc lineSlice(line: string; startCluster, endCluster: int): string =
  ## Extract the substring of `line` between `startCluster` and
  ## `endCluster` (exclusive). Cluster-indexed; safe for empty range.
  if startCluster >= endCluster: return ""
  let bounds = clusterBoundaries(line)
  let lo = clamp(startCluster, 0, bounds.len - 1)
  let hi = clamp(endCluster, 0, bounds.len - 1)
  line[bounds[lo] ..< bounds[hi]]

proc rowSegments(t: TextAreaWidget; row: DisplayRow):
    seq[tuple[text: string; color: string]] =
  ## Build the list of (text, color) segments for one display row.
  ## When no highlighter is installed, returns a single plain segment.
  ## Otherwise splits the row by highlight boundaries.
  result = @[]
  if row.lineIndex < 0 or row.lineIndex >= t.lines.len:
    return
  let line = t.lines[row.lineIndex]
  let body = lineSlice(line, row.startCluster, row.endCluster)
  if t.highlighter == nil:
    result.add (text: body, color: "")
    return
  let highlights = t.highlighter(line, row.lineIndex)
  if highlights.len == 0:
    result.add (text: body, color: "")
    return
  # Walk clusters within the row, switching colour at highlight
  # boundaries.
  var pos = row.startCluster
  while pos < row.endCluster:
    var color = ""
    var stop = row.endCluster
    # Pick the highlight that covers `pos`. When several overlap, the
    # last one in the list wins (mirrors the "last span wins" rule
    # used by `text/content.nim`).
    for h in highlights:
      if h.startCluster <= pos and pos < h.endCluster:
        color = colorForKind(h.kind)
        stop = min(h.endCluster, row.endCluster)
      elif h.startCluster > pos and h.startCluster < stop:
        stop = h.startCluster
    let seg = lineSlice(line, pos, stop)
    result.add (text: seg, color: color)
    pos = stop
  if result.len == 0:
    result.add (text: body, color: "")

proc cellWidthOfSegments(segs: seq[tuple[text: string; color: string]]): int =
  result = 0
  for s in segs:
    result += widthMod.displayWidth(s.text)

proc padSegmentsToWidth(t: TextAreaWidget;
                        segs: seq[tuple[text: string; color: string]]):
    seq[tuple[text: string; color: string]] =
  ## Tail-pad with spaces so the display row exactly fills the
  ## viewport width.
  result = segs
  let used = cellWidthOfSegments(result)
  if used < t.width:
    result.add (text: spaces(t.width - used), color: "")

proc renderTree*(t: TextAreaWidget) =
  ## Rebuild the visible children of `t.node`. Lays out:
  ##
  ##   * Optional top border row.
  ##   * `viewportHeight` body rows from `scrollY` onward in the
  ##     display-row sequence. Each body row is a sequence of coloured
  ##     segments built from the current highlighter (if any).
  ##     Cursor's display row is reverse-video.
  ##   * Optional bottom border row.
  let r = t.renderer
  clearTreeChildren(r, t.node)
  let glyphs = bordersGlyphs(t.border)
  let useBorder = t.border != bsNone
  let inner = max(1, t.width)
  if useBorder:
    emitRow(r, t.node, topBorderRow(glyphs, inner), t.borderColor)

  let rows = allDisplayRows(t)
  # Clamp scroll so cursor's row stays visible.
  if rows.len > 0:
    let curRow = displayRowOf(t, t.selection.cursor, rows)
    if curRow < t.scrollY:
      t.scrollY = curRow
    let bottom = t.scrollY + t.viewportHeight - 1
    if curRow > bottom:
      t.scrollY = curRow - t.viewportHeight + 1
    if t.scrollY < 0: t.scrollY = 0
    if t.scrollY > max(0, rows.len - t.viewportHeight):
      t.scrollY = max(0, rows.len - t.viewportHeight)

  let visibleCount = max(0, min(rows.len - t.scrollY, t.viewportHeight))
  for i in 0 ..< visibleCount:
    let absRow = t.scrollY + i
    let row = rows[absRow]
    var segs = rowSegments(t, row)
    segs = padSegmentsToWidth(t, segs)
    let leftEdge = if useBorder: glyphs.left else: ""
    let rightEdge = if useBorder: glyphs.right else: ""
    let isCursorRow =
      row.lineIndex == t.selection.cursor.line and
      t.selection.cursor.column >= row.startCluster and
      t.selection.cursor.column <= row.endCluster
    if isCursorRow and not t.hasSelection():
      # Reverse-video the cursor row to make the position visible
      # without a separate cursor cell.  Selection rendering is left
      # for a richer styled-runs pass in a later milestone.
      let totalText = block:
        var s = ""
        for seg in segs:
          s.add seg.text
        s
      emitRow(r, t.node, leftEdge & totalText & rightEdge, t.color,
              reverse = true)
    else:
      emitHighlightedRow(r, t.node, segs, leftEdge, rightEdge,
                         t.borderColor)

  # Pad the rest of the viewport so the widget's height doesn't jitter.
  for _ in visibleCount ..< t.viewportHeight:
    let body = spaces(inner)
    let line =
      if useBorder: glyphs.left & body & glyphs.right
      else: body
    emitRow(r, t.node, line, t.borderColor)

  if useBorder:
    emitRow(r, t.node, bottomBorderRow(glyphs, inner), t.borderColor)

# ----------------------------------------------------------------------------
# Mutation primitives — every public mutator funnels through here so
# the undo stack stays consistent.
# ----------------------------------------------------------------------------

proc fireOnChange(t: TextAreaWidget) =
  if t.onChange != nil:
    t.onChange(t.text)

proc pushUndo(t: TextAreaWidget; delta: EditDelta) =
  t.undoStack.add delta
  if t.maxUndoDepth > 0 and t.undoStack.len > t.maxUndoDepth:
    let drop = t.undoStack.len - t.maxUndoDepth
    var trimmed = newSeqOfCap[EditDelta](t.maxUndoDepth)
    for i in drop ..< t.undoStack.len:
      trimmed.add t.undoStack[i]
    t.undoStack = trimmed
  # Any new edit invalidates the redo stack.
  t.redoStack.setLen(0)

proc applyInsert(t: TextAreaWidget; pos: Caret; s: string) =
  ## Low-level insert at `pos`. `s` may contain `\n`. Updates `lines`,
  ## leaves cursor at the end of the inserted text. Does NOT touch the
  ## undo stack — callers (the public mutators) do that.
  let bounds = clusterBoundaries(t.lines[pos.line])
  let byteIns = bounds[clamp(pos.column, 0, bounds.len - 1)]
  let prefix = t.lines[pos.line][0 ..< byteIns]
  let suffix = t.lines[pos.line][byteIns ..< t.lines[pos.line].len]
  let parts = s.split('\n')
  if parts.len == 1:
    t.lines[pos.line] = prefix & s & suffix
    let inserted = clusterCount(s)
    t.selection.cursor = Caret(line: pos.line,
                               column: pos.column + inserted)
    t.selection.anchor = t.selection.cursor
  else:
    t.lines[pos.line] = prefix & parts[0]
    var insertIdx = pos.line + 1
    for i in 1 ..< parts.len - 1:
      t.lines.insert(parts[i], insertIdx)
      inc insertIdx
    let lastPart = parts[^1]
    t.lines.insert(lastPart & suffix, insertIdx)
    t.selection.cursor = Caret(line: insertIdx,
                               column: clusterCount(lastPart))
    t.selection.anchor = t.selection.cursor

proc applyDeleteRange(t: TextAreaWidget; a, b: Caret): string =
  ## Low-level delete [a, b). Returns the removed text (with `\n` for
  ## inter-line joins). Does NOT touch the undo stack.
  if a == b: return ""
  let lo = if a < b: a else: b
  let hi = if a < b: b else: a
  if lo.line == hi.line:
    let line = t.lines[lo.line]
    let bounds = clusterBoundaries(line)
    let bs = bounds[clamp(lo.column, 0, bounds.len - 1)]
    let be = bounds[clamp(hi.column, 0, bounds.len - 1)]
    let removed = line[bs ..< be]
    t.lines[lo.line] = line[0 ..< bs] & line[be ..< line.len]
    t.selection.cursor = lo
    t.selection.anchor = lo
    return removed
  else:
    var removed = ""
    let firstLine = t.lines[lo.line]
    let lastLine = t.lines[hi.line]
    let firstBounds = clusterBoundaries(firstLine)
    let lastBounds = clusterBoundaries(lastLine)
    let bs = firstBounds[clamp(lo.column, 0, firstBounds.len - 1)]
    let be = lastBounds[clamp(hi.column, 0, lastBounds.len - 1)]
    removed.add firstLine[bs ..< firstLine.len]
    for i in lo.line + 1 ..< hi.line:
      removed.add '\n'
      removed.add t.lines[i]
    removed.add '\n'
    removed.add lastLine[0 ..< be]
    let merged = firstLine[0 ..< bs] & lastLine[be ..< lastLine.len]
    t.lines[lo.line] = merged
    # Remove lines (lo.line, hi.line] inclusive from the original tail.
    let dropFrom = lo.line + 1
    let dropTo = hi.line
    let dropCount = dropTo - dropFrom + 1
    for _ in 0 ..< dropCount:
      t.lines.delete(dropFrom)
    t.selection.cursor = lo
    t.selection.anchor = lo
    return removed

# ----------------------------------------------------------------------------
# Public mutators — go through `pushUndo`.
# ----------------------------------------------------------------------------

proc deleteSelection*(t: TextAreaWidget): bool {.discardable.} =
  if not t.hasSelection(): return false
  if t.readOnly: return false
  let a = t.selStart
  let b = t.selEnd
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  let removed = applyDeleteRange(t, a, b)
  t.pushUndo EditDelta(
    op: eoReplace,
    replaceStart: a, replaceEnd: b,
    removed: removed, inserted: "",
    cursorBefore: cursorBefore, anchorBefore: anchorBefore,
    cursorAfter: a, anchorAfter: a)
  t.renderTree()
  fireOnChange(t)
  return true

proc insertText*(t: TextAreaWidget; s: string) =
  if t.readOnly: return
  if s.len == 0: return
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  if t.hasSelection():
    let a = t.selStart
    let b = t.selEnd
    let removed = applyDeleteRange(t, a, b)
    let pos = a
    applyInsert(t, pos, s)
    t.pushUndo EditDelta(
      op: eoReplace,
      replaceStart: a, replaceEnd: b,
      removed: removed, inserted: s,
      cursorBefore: cursorBefore, anchorBefore: anchorBefore,
      cursorAfter: t.selection.cursor,
      anchorAfter: t.selection.anchor)
  else:
    let pos = t.selection.cursor
    applyInsert(t, pos, s)
    t.pushUndo EditDelta(
      op: eoInsert,
      pos: pos, text: s,
      cursorBefore: cursorBefore, anchorBefore: anchorBefore,
      cursorAfter: t.selection.cursor,
      anchorAfter: t.selection.anchor)
  t.renderTree()
  fireOnChange(t)

proc backspace*(t: TextAreaWidget) =
  if t.readOnly: return
  if t.hasSelection():
    discard t.deleteSelection()
    return
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  let cur = t.selection.cursor
  if cur.line == 0 and cur.column == 0: return
  var prev: Caret
  if cur.column > 0:
    prev = Caret(line: cur.line, column: cur.column - 1)
  else:
    prev = Caret(line: cur.line - 1,
                 column: clusterCount(t.lines[cur.line - 1]))
  let removed = applyDeleteRange(t, prev, cur)
  t.pushUndo EditDelta(
    op: eoDelete,
    pos: prev, text: removed,
    cursorBefore: cursorBefore, anchorBefore: anchorBefore,
    cursorAfter: prev, anchorAfter: prev)
  t.renderTree()
  fireOnChange(t)

proc deleteRight*(t: TextAreaWidget) =
  if t.readOnly: return
  if t.hasSelection():
    discard t.deleteSelection()
    return
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  let cur = t.selection.cursor
  let lineN = clusterCount(t.lines[cur.line])
  var nxt: Caret
  if cur.column < lineN:
    nxt = Caret(line: cur.line, column: cur.column + 1)
  elif cur.line < t.lines.len - 1:
    nxt = Caret(line: cur.line + 1, column: 0)
  else:
    return
  let removed = applyDeleteRange(t, cur, nxt)
  t.pushUndo EditDelta(
    op: eoDelete,
    pos: cur, text: removed,
    cursorBefore: cursorBefore, anchorBefore: anchorBefore,
    cursorAfter: cur, anchorAfter: cur)
  t.renderTree()
  fireOnChange(t)

proc splitLine*(t: TextAreaWidget) =
  ## `Enter` — split the current line at the cursor, replacing any
  ## active selection.
  if t.readOnly: return
  if t.hasSelection():
    let a = t.selStart
    let b = t.selEnd
    let cursorBefore = t.selection.cursor
    let anchorBefore = t.selection.anchor
    let removed = applyDeleteRange(t, a, b)
    applyInsert(t, a, "\n")
    t.pushUndo EditDelta(
      op: eoReplace,
      replaceStart: a, replaceEnd: b,
      removed: removed, inserted: "\n",
      cursorBefore: cursorBefore, anchorBefore: anchorBefore,
      cursorAfter: t.selection.cursor,
      anchorAfter: t.selection.anchor)
  else:
    let cursorBefore = t.selection.cursor
    let anchorBefore = t.selection.anchor
    let pos = t.selection.cursor
    applyInsert(t, pos, "\n")
    t.pushUndo EditDelta(
      op: eoSplitLine,
      splitAt: pos,
      cursorBefore: cursorBefore, anchorBefore: anchorBefore,
      cursorAfter: t.selection.cursor,
      anchorAfter: t.selection.anchor)
  t.renderTree()
  fireOnChange(t)

# ----------------------------------------------------------------------------
# Word-boundary navigation + delete.
# ----------------------------------------------------------------------------

proc isWordCluster(s: string): bool =
  if s.len == 0: return false
  for r in runes(s):
    if r == Rune(' '.ord) or r == Rune('\t'.ord) or r == Rune('\n'.ord):
      return false
  return true

proc previousWordPos(t: TextAreaWidget; pos: Caret): Caret =
  ## Walk back over whitespace, then over word characters, mirroring
  ## `Ctrl+Left` semantics. Crosses line boundaries.
  var p = pos
  if p.column == 0 and p.line == 0: return p
  if p.column == 0:
    p = Caret(line: p.line - 1, column: clusterCount(t.lines[p.line - 1]))
    return p
  while p.column > 0 and
        not isWordCluster(clusterTextAt(t.lines[p.line], p.column - 1)):
    dec p.column
  while p.column > 0 and
        isWordCluster(clusterTextAt(t.lines[p.line], p.column - 1)):
    dec p.column
  p

proc nextWordPos(t: TextAreaWidget; pos: Caret): Caret =
  var p = pos
  let n = clusterCount(t.lines[p.line])
  if p.column >= n and p.line < t.lines.len - 1:
    return Caret(line: p.line + 1, column: 0)
  while p.column < n and
        isWordCluster(clusterTextAt(t.lines[p.line], p.column)):
    inc p.column
  while p.column < n and
        not isWordCluster(clusterTextAt(t.lines[p.line], p.column)):
    inc p.column
  p

proc deleteWordLeft*(t: TextAreaWidget) =
  if t.readOnly: return
  if t.hasSelection():
    discard t.deleteSelection()
    return
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  let to = previousWordPos(t, cursorBefore)
  if to == cursorBefore: return
  let removed = applyDeleteRange(t, to, cursorBefore)
  t.pushUndo EditDelta(
    op: eoDelete,
    pos: to, text: removed,
    cursorBefore: cursorBefore, anchorBefore: anchorBefore,
    cursorAfter: to, anchorAfter: to)
  t.renderTree()
  fireOnChange(t)

# ----------------------------------------------------------------------------
# Indent / dedent — soft tabs.
# ----------------------------------------------------------------------------

proc countLeadingSpaces(line: string; maxN: int): int =
  ## How many leading ASCII spaces on `line`, capped at `maxN`.
  result = 0
  for ch in line:
    if ch == ' ':
      inc result
      if result >= maxN: break
    else:
      break

proc indent*(t: TextAreaWidget) =
  ## `Tab` — insert `tabSize` spaces at cursor, OR indent every line in
  ## a multi-line selection by `tabSize` spaces.
  if t.readOnly: return
  let pad = spaces(t.tabSize)
  if t.hasSelection() and t.selStart.line != t.selEnd.line:
    let a = t.selStart
    let b = t.selEnd
    let cursorBefore = t.selection.cursor
    let anchorBefore = t.selection.anchor
    var inserted = 0
    for i in a.line .. b.line:
      t.lines[i] = pad & t.lines[i]
      inc inserted
    discard inserted
    # Bump anchor + cursor columns on their respective lines.
    var newA = a
    var newB = b
    newA.column += t.tabSize
    newB.column += t.tabSize
    if t.selection.anchor <= t.selection.cursor:
      t.selection.anchor = newA
      t.selection.cursor = newB
    else:
      t.selection.cursor = newA
      t.selection.anchor = newB
    # Indent of multiple lines is encoded as a single replace delta
    # whose removed/inserted strings carry the joined-by-newlines
    # block. This keeps `undo` simple.
    var removedBlock = ""
    var insertedBlock = ""
    for i in a.line .. b.line:
      if i > a.line:
        removedBlock.add '\n'
        insertedBlock.add '\n'
      let plain = t.lines[i][t.tabSize ..< t.lines[i].len]
      removedBlock.add plain
      insertedBlock.add t.lines[i]
    t.pushUndo EditDelta(
      op: eoReplace,
      replaceStart: Caret(line: a.line, column: 0),
      replaceEnd: Caret(line: b.line,
                        column: clusterCount(t.lines[b.line]) - t.tabSize),
      removed: removedBlock,
      inserted: insertedBlock,
      cursorBefore: cursorBefore, anchorBefore: anchorBefore,
      cursorAfter: t.selection.cursor,
      anchorAfter: t.selection.anchor)
    t.renderTree()
    fireOnChange(t)
  else:
    insertText(t, pad)

proc dedent*(t: TextAreaWidget) =
  ## `Shift+Tab` — remove up to `tabSize` leading ASCII spaces from
  ## the current line (or every selected line). No-op when the line
  ## has no leading spaces.
  if t.readOnly: return
  let lineRange =
    if t.hasSelection(): (t.selStart.line, t.selEnd.line)
    else: (t.selection.cursor.line, t.selection.cursor.line)
  let cursorBefore = t.selection.cursor
  let anchorBefore = t.selection.anchor
  var anyChanged = false
  var totalRemoved = 0
  var firstLineRemoved = 0
  var lastLineRemoved = 0
  for i in lineRange[0] .. lineRange[1]:
    let n = countLeadingSpaces(t.lines[i], t.tabSize)
    if n > 0:
      t.lines[i] = t.lines[i][n ..< t.lines[i].len]
      anyChanged = true
      totalRemoved += n
      if i == lineRange[0]: firstLineRemoved = n
      if i == lineRange[1]: lastLineRemoved = n
  if not anyChanged: return
  # Adjust selection.
  var c = t.selection.cursor
  var a = t.selection.anchor
  if c.line == lineRange[0]:
    c.column = max(0, c.column - firstLineRemoved)
  if c.line == lineRange[1] and lineRange[0] != lineRange[1]:
    c.column = max(0, c.column - lastLineRemoved)
  if a.line == lineRange[0]:
    a.column = max(0, a.column - firstLineRemoved)
  if a.line == lineRange[1] and lineRange[0] != lineRange[1]:
    a.column = max(0, a.column - lastLineRemoved)
  t.selection.cursor = c
  t.selection.anchor = a
  t.pushUndo EditDelta(
    op: eoReplace,
    replaceStart: Caret(line: lineRange[0], column: 0),
    replaceEnd: Caret(line: lineRange[1], column: 0),
    removed: spaces(totalRemoved),
    inserted: "",
    cursorBefore: cursorBefore, anchorBefore: anchorBefore,
    cursorAfter: c, anchorAfter: a)
  t.renderTree()
  fireOnChange(t)

# ----------------------------------------------------------------------------
# Cursor / selection movement.
# ----------------------------------------------------------------------------

proc moveCursorTo*(t: TextAreaWidget; pos: Caret;
                   selecting: bool = false) =
  let target = t.clampCaret(pos)
  if selecting:
    t.selection.cursor = target
  else:
    t.selection.cursor = target
    t.selection.anchor = target
  t.renderTree()

proc moveLeft*(t: TextAreaWidget; selecting: bool = false) =
  let cur = t.selection.cursor
  if t.hasSelection() and not selecting:
    t.moveCursorTo(t.selStart)
    return
  if cur.column > 0:
    t.moveCursorTo(Caret(line: cur.line, column: cur.column - 1),
                   selecting)
  elif cur.line > 0:
    t.moveCursorTo(Caret(line: cur.line - 1,
                         column: clusterCount(t.lines[cur.line - 1])),
                   selecting)

proc moveRight*(t: TextAreaWidget; selecting: bool = false) =
  let cur = t.selection.cursor
  if t.hasSelection() and not selecting:
    t.moveCursorTo(t.selEnd)
    return
  let n = clusterCount(t.lines[cur.line])
  if cur.column < n:
    t.moveCursorTo(Caret(line: cur.line, column: cur.column + 1),
                   selecting)
  elif cur.line < t.lines.len - 1:
    t.moveCursorTo(Caret(line: cur.line + 1, column: 0), selecting)

proc moveUp*(t: TextAreaWidget; selecting: bool = false) =
  let rows = allDisplayRows(t)
  if rows.len == 0: return
  let cur = t.selection.cursor
  let curRowIdx = displayRowOf(t, cur, rows)
  if curRowIdx == 0: return
  let prevRow = rows[curRowIdx - 1]
  let line = t.lines[prevRow.lineIndex]
  let target = clamp(cur.column, prevRow.startCluster,
                     min(prevRow.endCluster, clusterCount(line)))
  t.moveCursorTo(Caret(line: prevRow.lineIndex, column: target),
                 selecting)

proc moveDown*(t: TextAreaWidget; selecting: bool = false) =
  let rows = allDisplayRows(t)
  if rows.len == 0: return
  let cur = t.selection.cursor
  let curRowIdx = displayRowOf(t, cur, rows)
  if curRowIdx >= rows.len - 1: return
  let nextRow = rows[curRowIdx + 1]
  let line = t.lines[nextRow.lineIndex]
  let target = clamp(cur.column, nextRow.startCluster,
                     min(nextRow.endCluster, clusterCount(line)))
  t.moveCursorTo(Caret(line: nextRow.lineIndex, column: target),
                 selecting)

proc moveLineStart*(t: TextAreaWidget; selecting: bool = false) =
  let cur = t.selection.cursor
  t.moveCursorTo(Caret(line: cur.line, column: 0), selecting)

proc moveLineEnd*(t: TextAreaWidget; selecting: bool = false) =
  let cur = t.selection.cursor
  t.moveCursorTo(Caret(line: cur.line,
                       column: clusterCount(t.lines[cur.line])),
                 selecting)

proc moveDocStart*(t: TextAreaWidget; selecting: bool = false) =
  t.moveCursorTo(Caret(line: 0, column: 0), selecting)

proc moveDocEnd*(t: TextAreaWidget; selecting: bool = false) =
  if t.lines.len == 0:
    t.moveCursorTo(Caret(line: 0, column: 0), selecting)
    return
  let last = t.lines.len - 1
  t.moveCursorTo(Caret(line: last,
                       column: clusterCount(t.lines[last])),
                 selecting)

proc moveWordLeft*(t: TextAreaWidget; selecting: bool = false) =
  t.moveCursorTo(previousWordPos(t, t.selection.cursor), selecting)

proc moveWordRight*(t: TextAreaWidget; selecting: bool = false) =
  t.moveCursorTo(nextWordPos(t, t.selection.cursor), selecting)

proc selectAll*(t: TextAreaWidget) =
  t.selection.anchor = Caret(line: 0, column: 0)
  if t.lines.len == 0:
    t.selection.cursor = t.selection.anchor
  else:
    let last = t.lines.len - 1
    t.selection.cursor = Caret(line: last,
                               column: clusterCount(t.lines[last]))
  t.renderTree()

# ----------------------------------------------------------------------------
# Undo / redo.
# ----------------------------------------------------------------------------

proc applyUndoDelta(t: TextAreaWidget; d: EditDelta) =
  ## Reverse the effect of `d` on the document. The cursor + selection
  ## are reset to `d.cursorBefore`/`d.anchorBefore`.
  case d.op
  of eoInsert:
    let endPos = d.cursorAfter
    discard applyDeleteRange(t, d.pos, endPos)
  of eoDelete:
    applyInsert(t, d.pos, d.text)
  of eoSplitLine:
    let after = d.cursorAfter
    let before = d.splitAt
    discard applyDeleteRange(t, before, after)
  of eoJoinLines:
    discard d.origLineLen # not used by current code paths
  of eoReplace:
    let endPos = d.cursorAfter
    discard applyDeleteRange(t, d.replaceStart, endPos)
    if d.removed.len > 0:
      applyInsert(t, d.replaceStart, d.removed)
  t.selection.cursor = d.cursorBefore
  t.selection.anchor = d.anchorBefore

proc applyRedoDelta(t: TextAreaWidget; d: EditDelta) =
  ## Re-apply `d` after an undo. Mirrors the original mutator.
  case d.op
  of eoInsert:
    applyInsert(t, d.pos, d.text)
  of eoDelete:
    let endPos =
      if d.text.contains('\n'):
        d.cursorBefore
      else:
        Caret(line: d.pos.line,
              column: d.pos.column + clusterCount(d.text))
    discard applyDeleteRange(t, d.pos, endPos)
  of eoSplitLine:
    applyInsert(t, d.splitAt, "\n")
  of eoJoinLines:
    discard d.origLineLen
  of eoReplace:
    if d.removed.len > 0:
      let endPos = d.cursorBefore
      let lo = if d.replaceStart < endPos: d.replaceStart else: endPos
      let hi = if d.replaceStart < endPos: endPos else: d.replaceStart
      discard applyDeleteRange(t, lo, hi)
    if d.inserted.len > 0:
      applyInsert(t, d.replaceStart, d.inserted)
  t.selection.cursor = d.cursorAfter
  t.selection.anchor = d.anchorAfter

proc undo*(t: TextAreaWidget): bool {.discardable.} =
  if t.undoStack.len == 0: return false
  let d = t.undoStack[^1]
  t.undoStack.setLen(t.undoStack.len - 1)
  applyUndoDelta(t, d)
  t.redoStack.add d
  t.renderTree()
  fireOnChange(t)
  return true

proc redo*(t: TextAreaWidget): bool {.discardable.} =
  if t.redoStack.len == 0: return false
  let d = t.redoStack[^1]
  t.redoStack.setLen(t.redoStack.len - 1)
  applyRedoDelta(t, d)
  t.undoStack.add d
  t.renderTree()
  fireOnChange(t)
  return true

# ----------------------------------------------------------------------------
# Bulk text + language hooks.
# ----------------------------------------------------------------------------

proc setText*(t: TextAreaWidget; doc: string) =
  ## Replace the whole document. Clears undo/redo. Cursor lands at end.
  t.lines = doc.split('\n')
  if t.lines.len == 0: t.lines = @[""]
  t.undoStack.setLen(0)
  t.redoStack.setLen(0)
  let last = t.lines.len - 1
  t.selection.cursor = Caret(line: last, column: clusterCount(t.lines[last]))
  t.selection.anchor = t.selection.cursor
  t.renderTree()
  fireOnChange(t)

proc setLanguage*(t: TextAreaWidget; language: string) =
  ## Install a language stub highlighter. Tree-sitter integration is
  ## deferred for M19; the supported stubs cover the keyword colour
  ## tests in this milestone. Pass `""` to clear the highlighter.
  t.language = language
  case language.toLowerAscii
  of "python":
    t.highlighter = pythonKeywordHighlighter
  of "nim":
    t.highlighter = nimKeywordHighlighter
  of "":
    t.highlighter = nil
  else:
    t.highlighter = nil
  t.renderTree()

proc setHighlighter*(t: TextAreaWidget; h: HighlighterProc) =
  ## Install a custom highlighter. The widget calls `h(line, idx)` for
  ## each visible line at render time. Returning `@[]` means "no
  ## highlights for this line".
  t.highlighter = h
  t.renderTree()

# ----------------------------------------------------------------------------
# Key handling.
# ----------------------------------------------------------------------------

proc handleKey(t: TextAreaWidget; ev: TerminalEvent) =
  if t.disabled: return
  if ev.kind != ekKey: return
  let key = ev.key
  let name = key.key.toLowerAscii
  let mods = key.modifiers
  let shift = modShift in mods
  let ctrl  = modCtrl  in mods

  # Ctrl chords first — many of them shadow the printable codepoints.
  if ctrl and shift and name == "z":
    discard t.redo()
    return
  if ctrl and not shift:
    case name
    of "z":
      discard t.undo()
      return
    of "y":
      discard t.redo()
      return
    of "a":
      t.moveLineStart(selecting = false)
      return
    of "e":
      t.moveLineEnd(selecting = false)
      return
    of "left":
      t.moveWordLeft(selecting = false)
      return
    of "right":
      t.moveWordRight(selecting = false)
      return
    of "home":
      t.moveDocStart(selecting = false)
      return
    of "end":
      t.moveDocEnd(selecting = false)
      return
    of "w":
      t.deleteWordLeft()
      return
    else: discard

  case name
  of "left":
    t.moveLeft(selecting = shift)
    return
  of "right":
    t.moveRight(selecting = shift)
    return
  of "up":
    t.moveUp(selecting = shift)
    return
  of "down":
    t.moveDown(selecting = shift)
    return
  of "home":
    t.moveLineStart(selecting = shift)
    return
  of "end":
    t.moveLineEnd(selecting = shift)
    return
  of "backspace":
    t.backspace()
    return
  of "delete":
    t.deleteRight()
    return
  of "enter", "return":
    t.splitLine()
    return
  of "tab":
    if shift:
      t.dedent()
    else:
      t.indent()
    return
  else: discard

  # Other chord prefixes don't insert as text.
  if ctrl: return
  if modAlt in mods or modMeta in mods: return
  if key.kind == kkChar and key.rune >= 0x20'u32 and key.rune != 0x7F'u32:
    let r = Rune(key.rune.int32)
    var s = ""
    s.add $r
    t.insertText(s)

# ----------------------------------------------------------------------------
# Construction.
# ----------------------------------------------------------------------------

proc newTextArea*(renderer: TerminalRenderer;
                  text: string = "";
                  width: int = 40;
                  viewportHeight: int = 10;
                  border: BorderStyle = bsRound;
                  borderColor: string = "";
                  color: string = "";
                  tabSize: int = 4;
                  softWrap: bool = true;
                  readOnly: bool = false;
                  language: string = "";
                  disabled: bool = false;
                  maxUndoDepth: int = 0;
                  onChange: proc(newDoc: string) = nil): TextAreaWidget =
  ## Construct a TextArea. Mount via `r.appendChild(parent, w.node)`.
  ## Pass `language = "python"` (or "nim") to enable the stub
  ## highlighter; pass `language = ""` for plain text.
  let actualWidth = max(1, width)
  let actualVp = max(1, viewportHeight)
  let actualTab = max(1, tabSize)
  let node = renderer.createElement("textarea")
  renderer.setAttribute(node, "data-widget", "textarea")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "textarea")
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  if readOnly:
    renderer.setAttribute(node, "readonly", "true")
  let docLines =
    if text.len == 0: @[""]
    else: text.split('\n')
  let lastIdx = max(0, docLines.len - 1)
  let lastLine = if docLines.len > 0: docLines[lastIdx] else: ""
  let endCaret = Caret(line: lastIdx, column: clusterCount(lastLine))
  let t = TextAreaWidget(
    renderer: renderer, node: node,
    lines: docLines,
    selection: TextSelection(anchor: endCaret, cursor: endCaret),
    width: actualWidth,
    viewportHeight: actualVp,
    scrollY: 0,
    border: border, borderColor: borderColor, color: color,
    tabSize: actualTab,
    softWrap: softWrap,
    readOnly: readOnly,
    disabled: disabled,
    language: "",
    highlighter: nil,
    onChange: onChange,
    undoStack: @[],
    redoStack: @[],
    maxUndoDepth: maxUndoDepth)
  if language.len > 0:
    t.setLanguage(language)
  t.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    t.handleKey(ev))
  t

# ----------------------------------------------------------------------------
# Convenience accessors used by tests.
# ----------------------------------------------------------------------------

proc id*(t: TextAreaWidget): int {.inline.} = t.node.id

proc cursorLine*(t: TextAreaWidget): int {.inline.} =
  t.selection.cursor.line

proc cursorColumn*(t: TextAreaWidget): int {.inline.} =
  t.selection.cursor.column

proc undoDepth*(t: TextAreaWidget): int {.inline.} =
  t.undoStack.len

proc redoDepth*(t: TextAreaWidget): int {.inline.} =
  t.redoStack.len

proc displayRowCount*(t: TextAreaWidget): int =
  ## Number of soft-wrapped display rows the widget would currently
  ## emit. Useful for tests that assert wrapping happened.
  allDisplayRows(t).len

proc displayRowText*(t: TextAreaWidget; index: int): string =
  ## The plain text of display row `index`. Returns "" out of range.
  let rows = allDisplayRows(t)
  if index < 0 or index >= rows.len: return ""
  let r = rows[index]
  lineSlice(t.lines[r.lineIndex], r.startCluster, r.endCluster)
