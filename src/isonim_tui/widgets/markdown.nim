## widgets/markdown.nim — Tier-3d `Markdown` widget (M20).
##
## Port of `textual/widgets/markdown.py` (~1,710 LOC) — pragmatic core.
## A Markdown rendering widget that turns a CommonMark-subset document
## into a tree of styled rows that the M8 compositor flattens to cells.
##
## The CommonMark parser is a pure-Nim implementation embedded directly
## in this module — no FFI to LGPL `cmark`, no third-party dependency.
## It targets the load-bearing CommonMark essentials:
##
##   * ATX headings (`#` … `######`)
##   * Setext headings (`===` / `---` underlines)
##   * Paragraphs (lazy continuation)
##   * Bullet lists (`-`, `*`, `+`) and ordered lists (`1.`, `2.`, …)
##   * Fenced code blocks (` ``` ` and `~~~`) with optional info string
##   * Indented code blocks (four-space prefix)
##   * Block quotes (`>` prefix)
##   * Thematic breaks (`---`, `***`, `___`)
##   * Inline emphasis (`*em*`, `**strong**`, `_em_`, `__strong__`)
##   * Inline code (`` `code` ``)
##   * Links (`[text](url)`)
##   * Hard line breaks (two trailing spaces)
##
## Deferred (mark items as `[ ]` in the milestone deliverables):
##
##   * Tables (GFM extension, deferred)
##   * Footnotes (deferred)
##   * Image rendering inline (covered by M14 `Image` widget separately)
##   * HTML inlines (passed through as plain text)
##   * Reference-style links (parsed but rendered as plain `text`)
##
## Code-block syntax highlighting reuses the M19 `HighlighterProc`
## interface from `widgets/textarea.nim`. The default mapping wires
## info-string `python` and `nim` to the stub keyword highlighters
## from M19. Tree-sitter integration is deferred — when it lands, the
## same hook is enough to flip every code block over.
##
## Charter §1: every public type is a value object except the widget
## handle itself, which is a `ref` so callers can mutate `setMarkdown`
## after construction.

import std/[strutils, unicode]

import ../renderer
import ../css/properties
import ../text/width as widthMod
import ./borders
import ./textarea

# ----------------------------------------------------------------------------
# AST — value-typed block / inline nodes.
# ----------------------------------------------------------------------------

type
  MdInlineKind* = enum
    miText        ## Plain text
    miEmphasis    ## *italic*
    miStrong      ## **bold**
    miCode        ## `code`
    miLink        ## [text](url)
    miBreak       ## hard line break

  MdInline* = object
    case kind*: MdInlineKind
    of miText, miCode:
      text*: string
    of miEmphasis, miStrong:
      children*: seq[MdInline]
    of miLink:
      linkChildren*: seq[MdInline]
      url*: string
      title*: string
    of miBreak:
      discard

  MdBlockKind* = enum
    mbParagraph   ## Sequence of inlines
    mbHeading     ## ATX or setext heading at level 1..6
    mbCodeBlock   ## Fenced or indented code block
    mbQuote       ## Block quote — wraps another block list
    mbList        ## Bullet or ordered list
    mbHr          ## Thematic break
    mbBlank       ## Blank-line separator (kept so the renderer can
                  ## reproduce vertical rhythm explicitly)

  MdListItem* = object
    blocks*: seq[MdBlock]

  MdBlock* = object
    case kind*: MdBlockKind
    of mbParagraph:
      paragraph*: seq[MdInline]
    of mbHeading:
      level*: int
      headingInlines*: seq[MdInline]
      anchor*: string                 ## Slug of the heading text — used
                                      ## by the ToC sidebar.
    of mbCodeBlock:
      info*: string                   ## Info string ("python", "nim", …)
      codeLines*: seq[string]
    of mbQuote:
      quoted*: seq[MdBlock]
    of mbList:
      ordered*: bool
      startNumber*: int
      items*: seq[MdListItem]
    of mbHr:
      discard
    of mbBlank:
      discard

  MdDocument* = object
    blocks*: seq[MdBlock]

# ----------------------------------------------------------------------------
# Slug helper — used to build heading anchors for the ToC.
# ----------------------------------------------------------------------------

proc slugify*(text: string): string =
  ## Build a heading anchor: ASCII-fold to lower, spaces -> `-`, drop
  ## punctuation. Mirrors GitHub's heading-anchor convention closely
  ## enough for the ToC to be useful without pulling in a Unicode
  ## confusables table.
  result = newStringOfCap(text.len)
  var lastDash = false
  for r in runes(text):
    let c = $r
    if c.len == 1 and (c[0].isAlphaNumeric or c[0] == '_'):
      result.add c[0].toLowerAscii
      lastDash = false
    elif c.len == 1 and (c[0] == ' ' or c[0] == '-' or c[0] == '\t'):
      if not lastDash and result.len > 0:
        result.add '-'
        lastDash = true
    else:
      # Drop everything else (punctuation, multi-byte runes).
      discard
  while result.len > 0 and result[^1] == '-':
    result.setLen(result.len - 1)

# ----------------------------------------------------------------------------
# Inline parser — emphasis, strong, code spans, links, hard breaks.
# Pragmatic CommonMark: not flanking-perfect, but good enough for prose.
# ----------------------------------------------------------------------------

proc parseInlineImpl(s: string): seq[MdInline]

proc parseLink(s: string; i: var int): MdInline =
  ## Parse `[text](url)` starting at `s[i] == '['`. Returns a `miText`
  ## fallback when the closing pieces are missing.
  let start = i
  if i >= s.len or s[i] != '[':
    return MdInline(kind: miText, text: "")
  inc i
  var textBuf = ""
  var depth = 1
  while i < s.len and depth > 0:
    let c = s[i]
    if c == '\\' and i + 1 < s.len:
      textBuf.add s[i + 1]
      i += 2
      continue
    if c == '[':
      inc depth
      textBuf.add c
      inc i
      continue
    if c == ']':
      dec depth
      if depth == 0: break
      textBuf.add c
      inc i
      continue
    textBuf.add c
    inc i
  if i >= s.len or s[i] != ']':
    i = start + 1
    return MdInline(kind: miText, text: "[")
  inc i  # consume ']'
  if i >= s.len or s[i] != '(':
    # Reference-style or missing target — fall back to plain text.
    i = start + 1
    return MdInline(kind: miText, text: "[")
  inc i  # consume '('
  var url = ""
  var title = ""
  while i < s.len and s[i] != ')' and s[i] != ' ':
    url.add s[i]
    inc i
  if i < s.len and s[i] == ' ':
    inc i
    if i < s.len and s[i] == '"':
      inc i
      while i < s.len and s[i] != '"':
        title.add s[i]
        inc i
      if i < s.len: inc i  # closing '"'
    while i < s.len and s[i] != ')':
      inc i
  if i >= s.len or s[i] != ')':
    i = start + 1
    return MdInline(kind: miText, text: "[")
  inc i  # consume ')'
  let inner = parseInlineImpl(textBuf)
  result = MdInline(kind: miLink, linkChildren: inner,
                    url: url, title: title)

proc parseCodeSpan(s: string; i: var int): MdInline =
  ## Parse `` `code` `` starting at `s[i] == '`'`. Falls back to plain
  ## text on a missing closer.
  let start = i
  if i >= s.len or s[i] != '`':
    return MdInline(kind: miText, text: "")
  # Count opening backticks (CommonMark allows multi-tick fences).
  var ticks = 0
  while i < s.len and s[i] == '`':
    inc ticks
    inc i
  let bodyStart = i
  while i < s.len:
    if s[i] == '`':
      var run = 0
      let runStart = i
      while i < s.len and s[i] == '`':
        inc run
        inc i
      if run == ticks:
        let body = s[bodyStart ..< runStart]
        return MdInline(kind: miCode, text: body.strip(chars = {' '}))
      # otherwise skip past this run, keep scanning
    else:
      inc i
  # No closer — emit the literal backticks as text.
  i = start + 1
  MdInline(kind: miText, text: "`")

proc parseEmphasis(s: string; i: var int; marker: char;
                   strong: bool): MdInline =
  ## Parse `*em*` / `_em_` (strong=false) or `**bold**` / `__bold__`
  ## (strong=true) starting at `s[i] == marker`. Falls back to plain
  ## text when the closer is missing.
  let need = if strong: 2 else: 1
  let start = i
  # Verify opening marker run is exactly `need` long.
  var openRun = 0
  while i < s.len and s[i] == marker:
    inc openRun
    inc i
  if openRun != need:
    i = start + 1
    return MdInline(kind: miText, text: $marker)
  let bodyStart = i
  while i < s.len:
    if s[i] == marker:
      var run = 0
      let runStart = i
      while i < s.len and s[i] == marker:
        inc run
        inc i
      if run >= need:
        let body = s[bodyStart ..< runStart]
        let inner = parseInlineImpl(body)
        if strong:
          return MdInline(kind: miStrong, children: inner)
        else:
          return MdInline(kind: miEmphasis, children: inner)
    else:
      inc i
  i = start + 1
  MdInline(kind: miText, text: $marker)

proc parseInlineImpl(s: string): seq[MdInline] =
  ## Walk `s` left-to-right, splitting into inline nodes. Plain runs are
  ## coalesced into a single `miText`. Hard line break = two spaces at
  ## end of a line.
  result = @[]
  var buf = ""
  template flushBuf() =
    if buf.len > 0:
      result.add MdInline(kind: miText, text: buf)
      buf.setLen(0)
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '\\' and i + 1 < s.len:
      # Escape: copy the next char literally.
      buf.add s[i + 1]
      i += 2
      continue
    if c == '`':
      flushBuf()
      result.add parseCodeSpan(s, i)
      continue
    if c == '[':
      flushBuf()
      result.add parseLink(s, i)
      continue
    if c == '*' or c == '_':
      let runStart = i
      var run = 0
      while runStart + run < s.len and s[runStart + run] == c:
        inc run
      if run >= 2:
        flushBuf()
        result.add parseEmphasis(s, i, c, strong = true)
        continue
      elif run == 1:
        flushBuf()
        result.add parseEmphasis(s, i, c, strong = false)
        continue
    if c == '\n':
      # Treat embedded newlines as soft line breaks → single space.
      let isHard = buf.len >= 2 and buf[^1] == ' ' and buf[^2] == ' '
      if isHard:
        buf.setLen(buf.len - 2)
        flushBuf()
        result.add MdInline(kind: miBreak)
      else:
        # Soft break: replace with a single space, but coalesce.
        if buf.len > 0 and buf[^1] != ' ':
          buf.add ' '
      inc i
      continue
    buf.add c
    inc i
  flushBuf()

proc parseInline*(s: string): seq[MdInline] =
  ## Public entry to the inline parser. Strips a single trailing
  ## newline first — block parsers always feed trimmed lines.
  var trimmed = s
  while trimmed.len > 0 and trimmed[^1] == '\n':
    trimmed.setLen(trimmed.len - 1)
  parseInlineImpl(trimmed)

# ----------------------------------------------------------------------------
# Block parser.
# ----------------------------------------------------------------------------

proc isBlankLine(line: string): bool =
  for c in line:
    if c != ' ' and c != '\t': return false
  return true

proc isHrLine(line: string): bool =
  ## Thematic break: ≥3 of `-`, `*`, or `_` separated by optional
  ## spaces, no other characters.
  var stripped = ""
  for c in line:
    if c != ' ' and c != '\t': stripped.add c
  if stripped.len < 3: return false
  let m = stripped[0]
  if m != '-' and m != '*' and m != '_': return false
  for c in stripped:
    if c != m: return false
  return true

proc countLeadingSpacesIn(line: string): int =
  result = 0
  for c in line:
    if c == ' ': inc result
    elif c == '\t':
      result += 4 - (result mod 4)
    else: break

proc atxHeadingLevel(line: string): int =
  ## Returns the heading level (1..6) if `line` starts with an ATX
  ## heading, 0 otherwise.
  var i = 0
  let leading = countLeadingSpacesIn(line)
  if leading >= 4: return 0
  i = leading
  var hashes = 0
  while i < line.len and line[i] == '#':
    inc hashes
    inc i
  if hashes < 1 or hashes > 6: return 0
  if i < line.len and line[i] != ' ' and line[i] != '\t':
    return 0
  hashes

proc atxHeadingText(line: string; level: int): string =
  let leading = countLeadingSpacesIn(line)
  var i = leading + level
  while i < line.len and (line[i] == ' ' or line[i] == '\t'): inc i
  var ending = line.len
  # Trim trailing closing `#`s (CommonMark allows them).
  while ending > i and line[ending - 1] == ' ':
    dec ending
  var trail = ending
  while trail > i and line[trail - 1] == '#':
    dec trail
  if trail < ending and (trail == i or line[trail - 1] == ' '):
    ending = trail
    while ending > i and line[ending - 1] == ' ':
      dec ending
  line[i ..< ending]

proc setextLevel(line: string): int =
  ## A line composed of `=` chars => level 1; `-` => level 2; otherwise 0.
  var stripped = ""
  for c in line:
    if c != ' ' and c != '\t': stripped.add c
  if stripped.len == 0: return 0
  if stripped[0] == '=':
    for c in stripped:
      if c != '=': return 0
    return 1
  if stripped[0] == '-':
    for c in stripped:
      if c != '-': return 0
    return 2
  return 0

proc fencedCodeOpener(line: string): tuple[ok: bool; ch: char; len: int;
                                            indent: int; info: string] =
  ## Returns `(true, fenceChar, fenceLen, indent, infoString)` when
  ## `line` opens a fenced code block.
  let leading = countLeadingSpacesIn(line)
  if leading >= 4:
    return (false, ' ', 0, 0, "")
  var i = leading
  if i >= line.len: return (false, ' ', 0, 0, "")
  let c = line[i]
  if c != '`' and c != '~': return (false, ' ', 0, 0, "")
  var run = 0
  while i < line.len and line[i] == c:
    inc run
    inc i
  if run < 3: return (false, ' ', 0, 0, "")
  var info = ""
  while i < line.len:
    if line[i] != ' ' and line[i] != '\t':
      info.add line[i]
    inc i
  return (true, c, run, leading, info)

proc fencedCodeCloser(line: string; openCh: char; openLen: int): bool =
  let leading = countLeadingSpacesIn(line)
  if leading >= 4: return false
  var i = leading
  var run = 0
  while i < line.len and line[i] == openCh:
    inc run
    inc i
  if run < openLen: return false
  while i < line.len:
    if line[i] != ' ' and line[i] != '\t': return false
    inc i
  true

proc bulletMarker(line: string):
    tuple[ok: bool; indent: int; markerWidth: int; ordered: bool;
          startNumber: int] =
  ## Parse a list-item marker. Returns the indent before the marker
  ## and the marker's total width (including trailing space).
  let leading = countLeadingSpacesIn(line)
  if leading >= 4:
    return (false, 0, 0, false, 0)
  var i = leading
  if i >= line.len:
    return (false, 0, 0, false, 0)
  let c = line[i]
  if c == '-' or c == '*' or c == '+':
    if i + 1 < line.len and line[i + 1] != ' ' and line[i + 1] != '\t':
      return (false, 0, 0, false, 0)
    let markerW = if i + 1 < line.len: 2 else: 1
    return (true, leading, markerW, false, 0)
  if c.isDigit:
    var j = i
    var num = 0
    var digits = 0
    while j < line.len and line[j].isDigit:
      num = num * 10 + (line[j].ord - '0'.ord)
      inc digits
      inc j
      if digits > 9: return (false, 0, 0, false, 0)
    if j >= line.len: return (false, 0, 0, false, 0)
    if line[j] != '.' and line[j] != ')':
      return (false, 0, 0, false, 0)
    inc j
    if j < line.len and line[j] != ' ' and line[j] != '\t':
      return (false, 0, 0, false, 0)
    let markerW = j - i + 1
    return (true, leading, markerW, true, num)
  (false, 0, 0, false, 0)

proc isQuoteLine(line: string): bool =
  let leading = countLeadingSpacesIn(line)
  if leading >= 4: return false
  let i = leading
  i < line.len and line[i] == '>'

proc stripQuoteMarker(line: string): string =
  let leading = countLeadingSpacesIn(line)
  var i = leading
  if i < line.len and line[i] == '>':
    inc i
    if i < line.len and line[i] == ' ':
      inc i
  line[i ..< line.len]

proc parseBlocks(lines: seq[string]; startLine, endLine: int): seq[MdBlock]

proc collectListItem(lines: seq[string]; startLine, endLine: int;
                     itemIndent, contentIndent: int):
                       tuple[item: MdListItem; consumed: int] =
  ## Collect the lines belonging to a single list item, starting at
  ## `startLine` (which has the marker stripped already in the caller's
  ## first entry). Subsequent lines are part of the item if they are
  ## either blank or indented by ≥ `contentIndent` columns.
  var i = startLine
  var itemLines: seq[string] = @[]
  itemLines.add lines[i]
  inc i
  while i < endLine:
    let line = lines[i]
    if isBlankLine(line):
      itemLines.add ""
      inc i
      continue
    let indent = countLeadingSpacesIn(line)
    if indent >= contentIndent:
      # Strip exactly contentIndent spaces.
      var stripped = line
      var dropped = 0
      var k = 0
      while k < stripped.len and dropped < contentIndent:
        if stripped[k] == ' ':
          inc dropped
          inc k
        elif stripped[k] == '\t':
          dropped += 4 - (dropped mod 4)
          inc k
        else: break
      itemLines.add stripped[k ..< stripped.len]
      inc i
      continue
    # A new list marker at the same indent as ours — terminate.
    let m = bulletMarker(line)
    if m.ok and m.indent <= itemIndent:
      break
    # Otherwise, looser indent than the content column — terminate.
    break
  let blocks = parseBlocks(itemLines, 0, itemLines.len)
  (MdListItem(blocks: blocks), i - startLine)

proc parseBlocks(lines: seq[string]; startLine, endLine: int): seq[MdBlock] =
  result = @[]
  var i = startLine
  while i < endLine:
    let line = lines[i]
    # Blank line — emit a blank-block separator (collapsed runs).
    if isBlankLine(line):
      if result.len > 0 and result[^1].kind != mbBlank:
        result.add MdBlock(kind: mbBlank)
      inc i
      continue
    # Thematic break.
    if isHrLine(line) and countLeadingSpacesIn(line) < 4:
      result.add MdBlock(kind: mbHr)
      inc i
      continue
    # ATX heading.
    let lvl = atxHeadingLevel(line)
    if lvl > 0:
      let headingText = atxHeadingText(line, lvl)
      let inlines = parseInline(headingText)
      result.add MdBlock(kind: mbHeading, level: lvl,
                         headingInlines: inlines,
                         anchor: slugify(headingText))
      inc i
      continue
    # Fenced code block.
    let f = fencedCodeOpener(line)
    if f.ok:
      var codeLines: seq[string] = @[]
      inc i
      while i < endLine and not fencedCodeCloser(lines[i], f.ch, f.len):
        var stripped = lines[i]
        # Strip up to f.indent leading spaces.
        var dropped = 0
        var k = 0
        while k < stripped.len and dropped < f.indent and stripped[k] == ' ':
          inc dropped
          inc k
        codeLines.add stripped[k ..< stripped.len]
        inc i
      if i < endLine: inc i  # consume closer
      result.add MdBlock(kind: mbCodeBlock, info: f.info, codeLines: codeLines)
      continue
    # Indented code block (only when we'd otherwise start a paragraph,
    # i.e. previous block isn't a continuation candidate).
    let lead = countLeadingSpacesIn(line)
    if lead >= 4 and (result.len == 0 or
                      result[^1].kind in {mbBlank, mbHeading, mbHr,
                                          mbCodeBlock, mbList, mbQuote}):
      var codeLines: seq[string] = @[]
      while i < endLine:
        let l = lines[i]
        if isBlankLine(l):
          codeLines.add ""
          inc i
          continue
        let lI = countLeadingSpacesIn(l)
        if lI < 4: break
        # Strip 4 leading spaces.
        var dropped = 0
        var k = 0
        while k < l.len and dropped < 4 and l[k] == ' ':
          inc dropped
          inc k
        codeLines.add l[k ..< l.len]
        inc i
      # Trim trailing blank lines from the code block.
      while codeLines.len > 0 and codeLines[^1].len == 0:
        codeLines.setLen(codeLines.len - 1)
      result.add MdBlock(kind: mbCodeBlock, info: "", codeLines: codeLines)
      continue
    # Block quote.
    if isQuoteLine(line):
      var quoteLines: seq[string] = @[]
      while i < endLine and isQuoteLine(lines[i]):
        quoteLines.add stripQuoteMarker(lines[i])
        inc i
      let quoted = parseBlocks(quoteLines, 0, quoteLines.len)
      result.add MdBlock(kind: mbQuote, quoted: quoted)
      continue
    # List.
    let m = bulletMarker(line)
    if m.ok:
      let ordered = m.ordered
      let startNumber = m.startNumber
      var items: seq[MdListItem] = @[]
      while i < endLine:
        let lineNow = lines[i]
        if isBlankLine(lineNow):
          # Blank between items — keep going if next non-blank is
          # another marker; otherwise terminate.
          var look = i + 1
          while look < endLine and isBlankLine(lines[look]):
            inc look
          if look >= endLine: break
          let mNext = bulletMarker(lines[look])
          if not mNext.ok: break
          if mNext.ordered != ordered: break
          if mNext.indent != m.indent: break
          i = look
          continue
        let mm = bulletMarker(lineNow)
        if not mm.ok: break
        if mm.ordered != ordered: break
        if mm.indent != m.indent: break
        # Strip the marker from this line.
        let bodyStart = mm.indent + mm.markerWidth
        let firstBody =
          if bodyStart < lineNow.len: lineNow[bodyStart ..< lineNow.len]
          else: ""
        var rest = lines
        rest[i] = firstBody
        let contentIndent = mm.indent + mm.markerWidth
        let (item, consumed) = collectListItem(rest, i, endLine,
                                               mm.indent, contentIndent)
        items.add item
        i += consumed
      result.add MdBlock(kind: mbList, ordered: ordered,
                         startNumber: startNumber, items: items)
      continue
    # Paragraph: collect contiguous non-blank lines, with possible
    # setext heading underline as the second line.
    var paraLines: seq[string] = @[]
    paraLines.add line
    inc i
    var headingLevel = 0
    while i < endLine:
      let l = lines[i]
      if isBlankLine(l): break
      # Setext heading: closes the paragraph.
      let sl = setextLevel(l)
      if sl > 0 and paraLines.len >= 1:
        headingLevel = sl
        inc i
        break
      # New block start interrupts the paragraph.
      if isHrLine(l) and countLeadingSpacesIn(l) < 4: break
      if atxHeadingLevel(l) > 0: break
      let f2 = fencedCodeOpener(l)
      if f2.ok: break
      if isQuoteLine(l): break
      let m2 = bulletMarker(l)
      if m2.ok: break
      paraLines.add l
      inc i
    let merged = paraLines.join("\n")
    if headingLevel > 0:
      let inlines = parseInline(merged)
      result.add MdBlock(kind: mbHeading, level: headingLevel,
                         headingInlines: inlines,
                         anchor: slugify(merged))
    else:
      let inlines = parseInline(merged)
      result.add MdBlock(kind: mbParagraph, paragraph: inlines)

proc parseMarkdown*(source: string): MdDocument =
  ## Parse a CommonMark-subset document. The output is a value-typed
  ## block list ready to be rendered by `MarkdownWidget`.
  var lines = source.splitLines()
  # Drop the trailing empty line `splitLines` adds for a trailing `\n`.
  if lines.len > 0 and lines[^1].len == 0:
    lines.setLen(lines.len - 1)
  MdDocument(blocks: parseBlocks(lines, 0, lines.len))

# ----------------------------------------------------------------------------
# Inline rendering — flatten an inline list to a (text, color, bold,
# italic, link) tuple sequence.
# ----------------------------------------------------------------------------

type
  InlineSpan* = object
    text*: string
    color*: string
    bold*: bool
    italic*: bool
    underline*: bool

proc flattenInlines*(inlines: seq[MdInline];
                     bold = false; italic = false;
                     codeColor = "syntax-string";
                     linkColor = "blue"): seq[InlineSpan]

proc flattenInlines*(inlines: seq[MdInline];
                     bold = false; italic = false;
                     codeColor = "syntax-string";
                     linkColor = "blue"): seq[InlineSpan] =
  result = @[]
  for ix in inlines:
    case ix.kind
    of miText:
      result.add InlineSpan(text: ix.text, color: "",
                            bold: bold, italic: italic, underline: false)
    of miCode:
      result.add InlineSpan(text: ix.text, color: codeColor,
                            bold: bold, italic: italic, underline: false)
    of miEmphasis:
      let inner = flattenInlines(ix.children, bold, true, codeColor, linkColor)
      for s in inner: result.add s
    of miStrong:
      let inner = flattenInlines(ix.children, true, italic, codeColor,
                                 linkColor)
      for s in inner: result.add s
    of miLink:
      let inner = flattenInlines(ix.linkChildren, bold, italic,
                                 codeColor, linkColor)
      for s in inner:
        var copy = s
        if copy.color.len == 0:
          copy.color = linkColor
        copy.underline = true
        result.add copy
    of miBreak:
      result.add InlineSpan(text: "\n", color: "", bold: false,
                            italic: false, underline: false)

# ----------------------------------------------------------------------------
# Word-wrap a sequence of inline spans into rows of cells.
# ----------------------------------------------------------------------------

proc wrapSpans*(spans: seq[InlineSpan]; width: int): seq[seq[InlineSpan]] =
  ## Produce display rows. Each row's combined display width is ≤ `width`.
  ## Splits on whitespace and on hard breaks (`\n`).
  result = @[]
  if width <= 0:
    result.add spans
    return
  var current: seq[InlineSpan] = @[]
  var currentWidth = 0
  for span in spans:
    if span.text == "\n":
      result.add current
      current = @[]
      currentWidth = 0
      continue
    # Walk the span, breaking on spaces.
    var i = 0
    while i < span.text.len:
      # Collect a word and the run of whitespace that follows.
      let wordStart = i
      while i < span.text.len and span.text[i] != ' ' and
            span.text[i] != '\t' and span.text[i] != '\n':
        inc i
      let word = span.text[wordStart ..< i]
      let wsStart = i
      while i < span.text.len and (span.text[i] == ' ' or
                                   span.text[i] == '\t'):
        inc i
      let ws = span.text[wsStart ..< i]
      if word.len > 0:
        let w = widthMod.displayWidth(word)
        if currentWidth + w > width and currentWidth > 0:
          result.add current
          current = @[]
          currentWidth = 0
        # When the word alone is wider than the line, just take it
        # (CommonMark prefers not to break inside words).
        current.add InlineSpan(text: word, color: span.color,
                               bold: span.bold, italic: span.italic,
                               underline: span.underline)
        currentWidth += w
      if ws.len > 0:
        if currentWidth == 0:
          # Skip leading whitespace at row start.
          discard
        else:
          let w = widthMod.displayWidth(ws)
          if currentWidth + w > width:
            result.add current
            current = @[]
            currentWidth = 0
          else:
            current.add InlineSpan(text: ws, color: span.color,
                                   bold: span.bold, italic: span.italic,
                                   underline: span.underline)
            currentWidth += w
  if current.len > 0 or result.len == 0:
    result.add current

# ----------------------------------------------------------------------------
# Public widget value type
# ----------------------------------------------------------------------------

type
  MdHighlighter* = HighlighterProc

  MarkdownWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    document*: MdDocument
    width*: int                        ## Inner cell width.
    border*: BorderStyle
    borderColor*: string
    color*: string
    codeBlockColor*: string
    headingColor*: string
    quoteColor*: string
    linkColor*: string
    codeHighlighters*: seq[tuple[language: string; hl: HighlighterProc]]
                                       ## Map from info-string to a stub
                                       ## highlighter (Python, Nim, …).

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------

proc renderTree*(m: MarkdownWidget)
proc setMarkdown*(m: MarkdownWidget; source: string)
proc setHighlighter*(m: MarkdownWidget; language: string; hl: HighlighterProc)

# ----------------------------------------------------------------------------
# Tree helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitPlainRow(r: TerminalRenderer; parent: TerminalNode;
                  text: string; color: string = "";
                  bold: bool = false; italic: bool = false) =
  let row = r.createElement("div")
  if color.len > 0: r.setStyle(row, "color", color)
  if bold: r.setStyle(row, "bold", "true")
  if italic: r.setStyle(row, "italic", "true")
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(parent, row)

proc emitSpannedRow(r: TerminalRenderer; parent: TerminalNode;
                    spans: seq[InlineSpan]; width: int) =
  ## Emit one display row carrying potentially many styled segments.
  ## Pads the tail with spaces to `width`.
  let row = r.createElement("div")
  var totalWidth = 0
  for s in spans:
    if s.text.len == 0: continue
    let segBox = r.createElement("span")
    if s.color.len > 0: r.setStyle(segBox, "color", s.color)
    if s.bold: r.setStyle(segBox, "bold", "true")
    if s.italic: r.setStyle(segBox, "italic", "true")
    if s.underline: r.setStyle(segBox, "underline", "true")
    r.appendChild(segBox, r.createTextNode(s.text))
    r.appendChild(row, segBox)
    totalWidth += widthMod.displayWidth(s.text)
  if totalWidth < width:
    let padBox = r.createElement("span")
    r.appendChild(padBox, r.createTextNode(spaces(width - totalWidth)))
    r.appendChild(row, padBox)
  r.appendChild(parent, row)

proc renderInlines(m: MarkdownWidget; parent: TerminalNode;
                   inlines: seq[MdInline]; width: int;
                   bold = false; italic = false; color = "") =
  let codeColor =
    if m.codeBlockColor.len > 0: m.codeBlockColor else: "syntax-string"
  let linkColor = if m.linkColor.len > 0: m.linkColor else: "blue"
  var spans = flattenInlines(inlines, bold = bold, italic = italic,
                             codeColor = codeColor, linkColor = linkColor)
  if color.len > 0:
    var withColor: seq[InlineSpan] = @[]
    for s in spans:
      var ss = s
      if ss.color.len == 0: ss.color = color
      withColor.add ss
    spans = withColor
  let rows = wrapSpans(spans, width)
  for row in rows:
    emitSpannedRow(m.renderer, parent, row, width)

# ----------------------------------------------------------------------------
# Code-block rendering — one row per source line, syntax-highlighted via
# the optional `HighlighterProc` looked up by info string.
# ----------------------------------------------------------------------------

proc highlighterFor(m: MarkdownWidget; info: string): HighlighterProc =
  if info.len == 0: return nil
  let lower = info.toLowerAscii
  for (lang, hl) in m.codeHighlighters:
    if lang == lower: return hl
  return nil

proc renderCodeBlock(m: MarkdownWidget; parent: TerminalNode;
                     code: MdBlock; width: int) =
  doAssert code.kind == mbCodeBlock
  let r = m.renderer
  let codeColor =
    if m.codeBlockColor.len > 0: m.codeBlockColor else: "syntax-comment"
  let hl = m.highlighterFor(code.info)
  for idx, line in code.codeLines:
    if hl == nil:
      let trimmed = if line.len > width: line[0 ..< width] else: line
      let padded = padOrTruncate(trimmed, width)
      emitPlainRow(r, parent, padded, codeColor, bold = false,
                   italic = false)
    else:
      # Walk the line, split into (text, color) segments using the
      # highlights returned by `hl`. Mirrors `widgets/textarea.nim`'s
      # `rowSegments`.
      let highlights = hl(line, idx)
      var spans: seq[InlineSpan] = @[]
      if highlights.len == 0:
        spans.add InlineSpan(text: line, color: codeColor)
      else:
        # Build cluster-bound substrings.
        var pos = 0
        let total = line.runeLen  # close enough for ASCII fast path
        discard total
        # Simplified: assume ASCII byte == cluster for code highlights;
        # textarea.nim's stub also operates over byte words.
        while pos < line.len:
          var color = codeColor
          var stop = line.len
          for h in highlights:
            if h.startCluster <= pos and pos < h.endCluster:
              color = colorForKind(h.kind)
              stop = min(h.endCluster, line.len)
            elif h.startCluster > pos and h.startCluster < stop:
              stop = h.startCluster
          let seg = line[pos ..< stop]
          spans.add InlineSpan(text: seg, color: color)
          pos = stop
      let pads = if widthMod.displayWidth(line) < width:
                   spaces(width - widthMod.displayWidth(line))
                 else: ""
      var allSpans = spans
      if pads.len > 0:
        allSpans.add InlineSpan(text: pads, color: "")
      emitSpannedRow(r, parent, allSpans, width)

# ----------------------------------------------------------------------------
# Block rendering — recursive walk of the document.
# ----------------------------------------------------------------------------

proc renderBlocks(m: MarkdownWidget; parent: TerminalNode;
                  blocks: seq[MdBlock]; width: int; depth: int)

proc renderBlocks(m: MarkdownWidget; parent: TerminalNode;
                  blocks: seq[MdBlock]; width: int; depth: int) =
  let r = m.renderer
  for blk in blocks:
    case blk.kind
    of mbBlank:
      if width > 0:
        emitPlainRow(r, parent, spaces(width))
    of mbHr:
      let glyphs = bordersGlyphs(bsSolid)
      var line = ""
      var w = 0
      while w < width:
        line.add glyphs.horizontal
        w += widthMod.displayWidth(glyphs.horizontal)
      emitPlainRow(r, parent, line, m.borderColor)
    of mbHeading:
      let prefix =
        case blk.level
        of 1: "# "
        of 2: "## "
        of 3: "### "
        of 4: "#### "
        of 5: "##### "
        of 6: "###### "
        else: "# "
      let headingColor =
        if m.headingColor.len > 0: m.headingColor else: "primary"
      # Build the heading row with its `# ` prefix, then style + wrap.
      var spans: seq[InlineSpan] = @[]
      spans.add InlineSpan(text: prefix, color: headingColor, bold: true)
      let inner = flattenInlines(blk.headingInlines, bold = true,
                                 italic = false,
                                 codeColor = m.codeBlockColor,
                                 linkColor = m.linkColor)
      for s in inner:
        var ss = s
        if ss.color.len == 0: ss.color = headingColor
        ss.bold = true
        spans.add ss
      let rows = wrapSpans(spans, width)
      for rw in rows:
        emitSpannedRow(r, parent, rw, width)
    of mbParagraph:
      m.renderInlines(parent, blk.paragraph, width, color = m.color)
    of mbCodeBlock:
      m.renderCodeBlock(parent, blk, width)
    of mbQuote:
      # Render quoted block inset by `> ` prefix on each row.
      let quoteColor =
        if m.quoteColor.len > 0: m.quoteColor else: "syntax-comment"
      let innerWidth = max(1, width - 2)
      let inner = r.createElement("div")
      m.renderBlocks(inner, blk.quoted, innerWidth, depth + 1)
      # Walk rendered children, prefix each with `> `.
      for child in inner.children:
        let row = r.createElement("div")
        let prefixBox = r.createElement("span")
        r.setStyle(prefixBox, "color", quoteColor)
        r.appendChild(prefixBox, r.createTextNode("> "))
        r.appendChild(row, prefixBox)
        # Re-parent the inline children of `child` under `row`.
        while child.children.len > 0:
          let cc = child.children[0]
          r.removeChild(child, cc)
          r.appendChild(row, cc)
        r.appendChild(parent, row)
    of mbList:
      var idx = blk.startNumber
      for item in blk.items:
        let marker =
          if blk.ordered: $idx & ". "
          else: "- "
        let markerWidth = widthMod.displayWidth(marker)
        let innerWidth = max(1, width - markerWidth)
        let inner = r.createElement("div")
        m.renderBlocks(inner, item.blocks, innerWidth, depth + 1)
        var first = true
        for child in inner.children:
          let row = r.createElement("div")
          let prefixBox = r.createElement("span")
          r.appendChild(prefixBox,
                        r.createTextNode(if first: marker
                                         else: spaces(markerWidth)))
          r.appendChild(row, prefixBox)
          while child.children.len > 0:
            let cc = child.children[0]
            r.removeChild(child, cc)
            r.appendChild(row, cc)
          r.appendChild(parent, row)
          first = false
        if blk.ordered: inc idx

# ----------------------------------------------------------------------------
# Public renderTree.
# ----------------------------------------------------------------------------

proc renderTree*(m: MarkdownWidget) =
  let r = m.renderer
  clearTreeChildren(r, m.node)
  let glyphs = bordersGlyphs(m.border)
  let useBorder = m.border != bsNone
  let inner = max(1, m.width)
  if useBorder:
    emitPlainRow(r, m.node, topBorderRow(glyphs, inner), m.borderColor)
  let bodyHost =
    if useBorder:
      let host = r.createElement("div")
      r.appendChild(m.node, host)
      host
    else:
      m.node
  m.renderBlocks(bodyHost, m.document.blocks, inner, 0)
  if useBorder:
    emitPlainRow(r, m.node, bottomBorderRow(glyphs, inner), m.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newMarkdown*(renderer: TerminalRenderer;
                  source: string = "";
                  width: int = 80;
                  border: BorderStyle = bsNone;
                  borderColor: string = "";
                  color: string = "";
                  codeBlockColor: string = "";
                  headingColor: string = "";
                  quoteColor: string = "";
                  linkColor: string = ""): MarkdownWidget =
  ## Construct a Markdown widget. The source is parsed eagerly; the
  ## resulting AST is held on the widget so subsequent `setMarkdown`
  ## calls don't reallocate the renderer node graph.
  let actualWidth = max(1, width)
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "markdown")
  renderer.setAttribute(node, "class", "markdown")
  let m = MarkdownWidget(
    renderer: renderer, node: node,
    document: parseMarkdown(source),
    width: actualWidth,
    border: border,
    borderColor: borderColor,
    color: color,
    codeBlockColor: codeBlockColor,
    headingColor: headingColor,
    quoteColor: quoteColor,
    linkColor: linkColor,
    codeHighlighters: @[
      ("python", pythonKeywordHighlighter),
      ("nim", nimKeywordHighlighter)])
  m.renderTree()
  m

proc setMarkdown*(m: MarkdownWidget; source: string) =
  m.document = parseMarkdown(source)
  m.renderTree()

proc setHighlighter*(m: MarkdownWidget; language: string;
                     hl: HighlighterProc) =
  let lower = language.toLowerAscii
  for i in 0 ..< m.codeHighlighters.len:
    if m.codeHighlighters[i].language == lower:
      m.codeHighlighters[i] = (lower, hl)
      m.renderTree()
      return
  m.codeHighlighters.add (lower, hl)
  m.renderTree()

# ----------------------------------------------------------------------------
# Convenience accessors used by tests.
# ----------------------------------------------------------------------------

proc id*(m: MarkdownWidget): int {.inline.} = m.node.id

proc blockCount*(m: MarkdownWidget): int {.inline.} =
  m.document.blocks.len

proc collectHeadingTextInline(inlines: seq[MdInline]): string =
  result = ""
  for ix in inlines:
    case ix.kind
    of miText, miCode:
      result.add ix.text
    of miEmphasis, miStrong:
      for cc in ix.children:
        if cc.kind in {miText, miCode}: result.add cc.text
    of miLink:
      for cc in ix.linkChildren:
        if cc.kind in {miText, miCode}: result.add cc.text
    of miBreak:
      result.add ' '

proc walkHeadings(blocks: seq[MdBlock];
                  acc: var seq[tuple[level: int; text: string;
                                      anchor: string]]) =
  for b in blocks:
    case b.kind
    of mbHeading:
      let plain = collectHeadingTextInline(b.headingInlines)
      acc.add (level: b.level, text: plain, anchor: b.anchor)
    of mbQuote:
      walkHeadings(b.quoted, acc)
    of mbList:
      for item in b.items:
        walkHeadings(item.blocks, acc)
    else: discard

proc headings*(m: MarkdownWidget): seq[tuple[level: int; text: string;
                                              anchor: string]] =
  ## Walk the document for the table-of-contents listing.
  result = @[]
  walkHeadings(m.document.blocks, result)

proc inlineToPlain(inlines: seq[MdInline]): string =
  result = ""
  for ix in inlines:
    case ix.kind
    of miText, miCode:
      result.add ix.text
    of miEmphasis, miStrong:
      result.add inlineToPlain(ix.children)
    of miLink:
      result.add inlineToPlain(ix.linkChildren)
    of miBreak:
      result.add '\n'

proc blocksToPlain(blocks: seq[MdBlock]; acc: var string) =
  for b in blocks:
    case b.kind
    of mbHeading:
      acc.add repeat('#', b.level)
      acc.add ' '
      acc.add inlineToPlain(b.headingInlines)
      acc.add '\n'
    of mbParagraph:
      acc.add inlineToPlain(b.paragraph)
      acc.add '\n'
    of mbCodeBlock:
      for ln in b.codeLines:
        acc.add ln
        acc.add '\n'
    of mbHr:
      acc.add "---\n"
    of mbBlank:
      acc.add '\n'
    of mbQuote:
      blocksToPlain(b.quoted, acc)
    of mbList:
      for item in b.items:
        blocksToPlain(item.blocks, acc)

proc plainText*(m: MarkdownWidget): string =
  ## Reconstruct a plain-text approximation of the document.
  ## Useful for tests that check structure independent of styling.
  result = ""
  blocksToPlain(m.document.blocks, result)
