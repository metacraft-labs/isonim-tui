## Rich text container — Nim port of `textual/content.py`.
##
## A `Content` is *immutable* plain text plus a sequence of style
## `Span`s that mark byte ranges with a `Style`. Operations return
## fresh `Content` values; the source is never mutated. This is
## deliberately the same contract as Textual's Python implementation:
## immutability lets every layer cache aggressively (cell length, line
## wrapping, diff hashes).
##
## Charter §1: every public type is a value `object`. We use
## `seq[Span]` and `string` for storage — both copy cheaply via Nim's
## value semantics under arc/orc, and never escape as `ref`/`ptr`.
##
## Ported subset:
##   * Content type (plain + spans)
##   * cellLength, len
##   * append, append_text
##   * assemble (constructor from a list of (text, style) chunks)
##   * lines (split by '\n', returning a seq[Content])
##   * truncate (with ellipsis option)
##   * rstrip (default-whitespace and explicit-character forms)
##   * highlight (regex-keyed style application — uses std/re)
##   * wrap (hard- and soft-wrap, grapheme-aware)
##
## Methods we deliberately defer to a later milestone (e.g. M5 / M7):
##   * full from_markup / from_rich_text BBCode-style parser (M5 — the
##     CSS / markup engine)
##   * render_strips (depends on the compositor — M2 / M8)
##   * get_optimal_width / get_height / get_minimal_width (depend on
##     CSS rules — M5)
##
## All ported methods have one-to-one tests in
## `tests/test_content_*.nim`.

import std/strutils
import std/re

import ./width
import ./ansi

# ----------------------------------------------------------------------------
# Span — a (start, end, style) annotation over byte offsets in plain text.
# ----------------------------------------------------------------------------

type
  Span* = object
    ## Style applied to a byte range. `start` and `stop` are byte
    ## offsets into `Content.plain`. `stop` is exclusive.
    start*: int
    stop*: int
    style*: Style

proc newSpan*(start, stop: int; style: Style): Span {.inline.} =
  Span(start: start, stop: stop, style: style)

proc `==`*(a, b: Span): bool {.inline.} =
  a.start == b.start and a.stop == b.stop and a.style == b.style

proc shift(s: Span; distance: int): Span {.inline.} =
  Span(start: max(0, s.start + distance), stop: s.stop + distance,
       style: s.style)

# ----------------------------------------------------------------------------
# Content — immutable plain text with style spans.
# ----------------------------------------------------------------------------

type
  Content* = object
    ## Immutable rich-text container. `plain` is the raw string;
    ## `spans` records styled byte ranges. Construct via `newContent`,
    ## `assemble`, or `fromString`.
    plain*: string
    spans*: seq[Span]

proc newContent*(plain: string = ""; spans: seq[Span] = @[]): Content =
  Content(plain: plain, spans: spans)

proc fromString*(s: string): Content {.inline.} =
  Content(plain: s, spans: @[])

proc empty*(_: typedesc[Content]): Content {.inline.} = newContent()

proc styled*(text: string; style: Style): Content =
  ## Build a Content with one span covering all of `text`.
  if text.len == 0: return Content(plain: "", spans: @[])
  Content(plain: text, spans: @[Span(start: 0, stop: text.len, style: style)])

proc len*(c: Content): int {.inline.} = c.plain.len

proc cellLength*(c: Content): int {.inline.} =
  ## Number of terminal cells the plain text occupies, grapheme-aware.
  displayWidth(c.plain)

proc `==`*(a, b: Content): bool =
  if a.plain != b.plain: return false
  if a.spans.len != b.spans.len: return false
  for i in 0 ..< a.spans.len:
    if a.spans[i] != b.spans[i]: return false
  return true

proc isSame*(a, b: Content): bool {.inline.} = a == b

# ----------------------------------------------------------------------------
# Append / Assemble
# ----------------------------------------------------------------------------

proc append*(c: Content; other: Content): Content =
  ## Concatenate two Contents. `other`'s spans are shifted by
  ## `c.plain.len`.
  if other.plain.len == 0 and other.spans.len == 0: return c
  result.plain = c.plain & other.plain
  result.spans = c.spans
  for s in other.spans:
    result.spans.add(shift(s, c.plain.len))

proc append*(c: Content; other: string): Content =
  if other.len == 0: return c
  Content(plain: c.plain & other, spans: c.spans)

proc appendText*(c: Content; text: string; style: Style): Content =
  ## Concatenate a styled chunk.
  if text.len == 0: return c
  result.plain = c.plain & text
  result.spans = c.spans
  result.spans.add(Span(start: c.plain.len,
                        stop: c.plain.len + text.len,
                        style: style))

proc assemble*(parts: openArray[(string, Style)]): Content =
  ## Build a Content from a sequence of (text, style) pairs. Each
  ## non-empty chunk gets its own Span; chunks with `defaultStyle()`
  ## still get a span (callers can simplify later).
  result.plain = ""
  result.spans = @[]
  for (text, style) in parts:
    if text.len == 0: continue
    let start = result.plain.len
    result.plain.add(text)
    result.spans.add(Span(start: start, stop: result.plain.len, style: style))

proc assemble*(parts: openArray[string]): Content =
  ## Plain-string overload — every chunk gets `defaultStyle()`.
  result.plain = ""
  result.spans = @[]
  for text in parts:
    if text.len == 0: continue
    result.plain.add(text)

# ----------------------------------------------------------------------------
# Lines — split on '\n'.
# ----------------------------------------------------------------------------

proc trimSpansToRange(spans: seq[Span]; start, stop: int): seq[Span] =
  ## Clip spans to the half-open byte range [start, stop) and re-base
  ## them so offsets are relative to `start`.
  for s in spans:
    if s.stop <= start or s.start >= stop: continue
    let lo = max(s.start, start) - start
    let hi = min(s.stop, stop) - start
    if hi <= lo: continue
    result.add(Span(start: lo, stop: hi, style: s.style))

proc lines*(c: Content): seq[Content] =
  ## Split on '\n'. The newline character itself is *not* included in
  ## the returned lines (matches Textual's Python `splitlines`-style
  ## behaviour for soft-line iteration).
  result = @[]
  if c.plain.len == 0:
    return @[c]
  var i = 0
  var lineStart = 0
  while i < c.plain.len:
    if c.plain[i] == '\n':
      let lineText = c.plain[lineStart ..< i]
      let lineSpans = trimSpansToRange(c.spans, lineStart, i)
      result.add(Content(plain: lineText, spans: lineSpans))
      lineStart = i + 1
    inc i
  let tail = c.plain[lineStart ..< c.plain.len]
  let tailSpans = trimSpansToRange(c.spans, lineStart, c.plain.len)
  result.add(Content(plain: tail, spans: tailSpans))

# ----------------------------------------------------------------------------
# Truncate — preserve cells, optional ellipsis.
# ----------------------------------------------------------------------------

proc truncate*(c: Content; maxCells: int;
               ellipsis: bool = false; padChar: string = " "): Content =
  ## Truncate to at most `maxCells` cells. With `ellipsis = true`, an
  ## ASCII "…" replaces the last cell of the cropped string. With
  ## `padChar` (always a single-cell string), pads up to `maxCells`
  ## when the input is shorter.
  if maxCells <= 0:
    return Content(plain: "", spans: @[])
  let cur = c.cellLength
  if cur == maxCells:
    return c
  if cur < maxCells:
    # pad right with `padChar`
    var pad = ""
    for _ in 0 ..< (maxCells - cur):
      pad.add(padChar)
    return Content(plain: c.plain & pad, spans: c.spans)
  # crop: walk grapheme clusters until we'd exceed maxCells
  var cellCount = 0
  var byteEnd = 0
  for cluster in graphemeClusters(c.plain):
    let cw = clusterDisplayWidth(cluster.text)
    if cellCount + cw > maxCells: break
    cellCount += cw
    byteEnd = cluster.stop
  var truncated = c.plain[0 ..< byteEnd]
  var newSpans = trimSpansToRange(c.spans, 0, byteEnd)
  if ellipsis and maxCells >= 1:
    # Replace last cell-worth with "…"
    if cellCount == maxCells:
      # Need to drop one cluster's worth, then add ellipsis.
      var rolled = 0
      var newEnd = 0
      var clusters: seq[(int, int, int)] = @[] # (start, stop, width)
      for cluster in graphemeClusters(c.plain[0 ..< byteEnd]):
        let cw = clusterDisplayWidth(cluster.text)
        clusters.add((cluster.start, cluster.stop, cw))
      if clusters.len > 0:
        rolled = clusters[^1][2]
        newEnd = clusters[^1][0]
        truncated = c.plain[0 ..< newEnd] & "\xe2\x80\xa6"  # "…" UTF-8
        newSpans = trimSpansToRange(c.spans, 0, newEnd)
        # Style the ellipsis with the last span's style if any.
        # (Textual keeps the trailing style; we follow.)
        if c.spans.len > 0:
          let lastStyle = c.spans[^1].style
          newSpans.add(Span(start: newEnd,
                            stop: newEnd + 3, style: lastStyle))
        discard rolled
    else:
      truncated.add("\xe2\x80\xa6")
  return Content(plain: truncated, spans: newSpans)

# ----------------------------------------------------------------------------
# rstrip — drop trailing whitespace (or explicit chars).
# ----------------------------------------------------------------------------

proc rstrip*(c: Content; chars: string = ""): Content =
  ## Strip trailing whitespace from `plain`. With `chars` non-empty,
  ## strip the given character set instead. Spans are clipped.
  let trimmed =
    if chars.len == 0: c.plain.strip(leading = false, trailing = true)
    else: c.plain.strip(leading = false, trailing = true,
                        chars = {chars[0]} + (
                          if chars.len > 1: {chars[1]} else: {}) +
                        (if chars.len > 2: {chars[2]} else: {}))
  if trimmed.len == c.plain.len:
    return c
  return Content(plain: trimmed,
                 spans: trimSpansToRange(c.spans, 0, trimmed.len))

# ----------------------------------------------------------------------------
# Highlight — apply a Style to every regex match.
# ----------------------------------------------------------------------------

proc highlight*(c: Content; pattern: string; style: Style): Content =
  ## Apply `style` to every (non-overlapping) match of `pattern` in
  ## `c.plain`. Existing spans are preserved.
  ##
  ## Note: uses `std/re` (PCRE) which is the standard Nim regex
  ## library. Patterns must be PCRE-compatible.
  if c.plain.len == 0: return c
  let r = re(pattern)
  var added: seq[Span] = @[]
  var startIdx = 0
  while startIdx <= c.plain.len:
    let m = c.plain.findBounds(r, start = startIdx)
    if m.first < 0: break
    if m.last < m.first: break
    added.add(Span(start: m.first, stop: m.last + 1, style: style))
    startIdx = m.last + 1
    if m.first == m.last and startIdx <= c.plain.len:
      inc startIdx  # avoid infinite loop on zero-width matches
  return Content(plain: c.plain, spans: c.spans & added)

# ----------------------------------------------------------------------------
# Wrap — soft and hard line wrapping, grapheme-aware.
# ----------------------------------------------------------------------------

type
  WrapMode* = enum
    wmSoft   ## word-wrap at whitespace; never split a grapheme cluster
    wmHard   ## hard wrap at `width` cells; never split a grapheme cluster
    wmFold   ## same as hard, but mid-word breaks honoured for very long words

proc accumulatedClusterWidths(text: string):
    seq[tuple[start, stop, width: int]] =
  ## Helper — return the byte spans + cell width of each cluster.
  for cluster in graphemeClusters(text):
    result.add((cluster.start, cluster.stop, clusterDisplayWidth(cluster.text)))

proc isAsciiSpace(line: string; cl: tuple[start, stop, width: int]): bool =
  (cl.stop - cl.start == 1) and line[cl.start] == ' '

proc wrapLine(line: Content; width: int;
              mode: WrapMode): seq[Content] =
  ## Wrap a single line (no embedded '\n') to ≤ `width` cells per
  ## output line. Never splits a grapheme cluster.
  ##
  ## Soft wrap (wmSoft) prefers to break at whitespace; the trailing
  ## space on a wrapped line is consumed and not carried to the next
  ## line. Hard wrap (wmHard) breaks at the cluster boundary that
  ## first overflows. Fold (wmFold) is identical to hard for ASCII;
  ## reserved for future kinking behaviour.
  result = @[]
  if width <= 0:
    result.add(line)
    return
  let clusters = accumulatedClusterWidths(line.plain)
  if clusters.len == 0:
    result.add(line)
    return

  var lineStart = 0    # byte offset where the current output line starts
  var i = 0            # cluster index for `lineStart`
  while i < clusters.len:
    var lastSpaceIdx = -1   # cluster index of the last space we consumed
    var pos = i
    var cells = 0
    # Greedily consume clusters into the current line.
    while pos < clusters.len and cells + clusters[pos].width <= width:
      if isAsciiSpace(line.plain, clusters[pos]):
        lastSpaceIdx = pos
      cells += clusters[pos].width
      inc pos
    if pos == clusters.len:
      # Tail fits — emit and stop.
      let part = line.plain[lineStart ..< line.plain.len]
      let partSpans = trimSpansToRange(line.spans, lineStart, line.plain.len)
      result.add(Content(plain: part, spans: partSpans))
      break

    # Overflow at clusters[pos]. Pick break point.
    var sliceStop, nextStart: int

    if isAsciiSpace(line.plain, clusters[pos]):
      # Overflow IS a space — consume it as the soft break.
      sliceStop = clusters[pos].start
      nextStart = clusters[pos].stop
    elif mode == wmSoft and lastSpaceIdx >= i:
      # Break at the previous space within the current line; consume it.
      sliceStop = clusters[lastSpaceIdx].start
      nextStart = clusters[lastSpaceIdx].stop
    elif pos > i:
      # No space available for soft break (or wmHard); break at the
      # overflow cluster.
      sliceStop = clusters[pos].start
      nextStart = clusters[pos].start
    else:
      # First cluster wider than `width`. Emit it alone to make forward
      # progress.
      sliceStop = clusters[i].stop
      nextStart = clusters[i].stop

    let part = line.plain[lineStart ..< sliceStop]
    let partSpans = trimSpansToRange(line.spans, lineStart, sliceStop)
    result.add(Content(plain: part, spans: partSpans))
    lineStart = nextStart
    # Advance i to the cluster whose `start == nextStart`.
    while i < clusters.len and clusters[i].start < nextStart:
      inc i

  if result.len == 0:
    result.add(line)

proc wrap*(c: Content; width: int;
           mode: WrapMode = wmSoft): seq[Content] =
  ## Wrap `c` to lines no wider than `width` cells. Existing '\n' in
  ## `plain` always force a break. When `mode` is `wmSoft`, prefer to
  ## break at the last whitespace within `width`; if no whitespace
  ## exists, fall through to hard-break behaviour. Never splits a
  ## grapheme cluster.
  result = @[]
  if width <= 0:
    result.add(c)
    return
  for line in lines(c):
    if line.cellLength <= width:
      result.add(line)
      continue
    for piece in wrapLine(line, width, mode):
      result.add(piece)

# ----------------------------------------------------------------------------
# Render to ANSI byte stream.
# ----------------------------------------------------------------------------

proc styleAtOffset*(c: Content; offset: int): Style =
  ## Return the topmost (last-added wins) style covering byte `offset`.
  var s = defaultStyle()
  for sp in c.spans:
    if sp.start <= offset and offset < sp.stop:
      s = sp.style
  return s

proc toAnsi*(c: Content; baseStyle: Style = defaultStyle()): string =
  ## Render to a string of UTF-8 bytes interleaved with SGR escapes,
  ## suitable for writing directly to a terminal. Walks the plain
  ## string by byte-offset, transitioning style when a span boundary is
  ## crossed.
  if c.plain.len == 0: return ""
  result = ""
  var prev = baseStyle
  var i = 0
  while i < c.plain.len:
    let s = styleAtOffset(c, i)
    if s != prev:
      result.add(renderSgr(prev, s))
      prev = s
    result.add(c.plain[i])
    inc i
  if prev != baseStyle:
    result.add(renderSgr(prev, baseStyle))

# Re-export for convenience.
export Style, defaultStyle, newStyle, renderSgr, reset
