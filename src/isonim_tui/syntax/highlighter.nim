## syntax/highlighter.nim — tree-sitter-driven syntax highlighting for
## the M19 `TextArea` widget.
##
## Walks the parse tree produced by `treesitter_ffi.parseString`, maps
## each leaf's `nodeType` to a small `HighlightKind` palette, and emits
## a flat `seq[Highlight]` of byte-aligned token spans.
##
## ## Mapping strategy
##
## tree-sitter grammars surface dozens of node-type names; the editor
## needs only a fixed palette to colour cells (mirrors the
## `colorForKind` palette in `widgets/textarea.nim`). We use a
## simple lookup over the **leaf** node-type names — anonymous tokens
## (`"proc"`, `"+"`, `"="`) carry the literal source text as their
## type, while named leaves (`comment`, `string_literal`, `identifier`,
## `integer_literal`) carry a category name.
##
## This is deliberately simpler than Textual's `.scm`-query path; the
## M19 spec did not require Scheme query support and a node-type-name
## table covers the load-bearing visual cases (keywords, strings,
## numbers, comments, identifiers).
##
## ## Per-line projection
##
## The `TextArea` widget paints highlights one **logical line** at a
## time and indexes them by **grapheme cluster**, not by byte. After
## the parse, we project each token's byte span onto the originating
## line and convert byte offsets to cluster indices via the grapheme
## iterator. Spans that cross line boundaries (e.g. multi-line strings,
## block comments) are split into per-line slices.

import std/strutils

import ./treesitter_ffi
import ../text/width as widthMod
import ../widgets/textarea as taMod

export Highlight, HighlightKind

# ----------------------------------------------------------------------------
# Public token type — pre-projection. The widget calls
# `lineHighlights` to project a parse onto its per-line index.
# ----------------------------------------------------------------------------

type
  Token* = object
    ## A single highlighted run from the parse, keyed by absolute byte
    ## span. Multiple tokens may belong to the same line; multi-line
    ## tokens are emitted as a single span and projected later.
    startByte*: int
    endByte*: int
    kind*: HighlightKind
    nodeType*: string  ## The originating tree-sitter node type — kept
                       ## for debugging / for tests asserting which
                       ## category the mapping picked.

# ----------------------------------------------------------------------------
# Node-type → HighlightKind mapping.
#
# Anonymous tokens in tree-sitter grammars carry their literal source
# text as their node type — `proc`, `if`, `=`, `(`. Named tokens carry
# semantic names — `comment`, `integer_literal`, `string_literal`.
# We resolve both via the same lookup: keywords are matched literally,
# semantic categories are matched by name.
# ----------------------------------------------------------------------------

const NimKeywordTokens = [
  # Keywords from the Nim manual. The tree-sitter-nim grammar emits
  # each as an anonymous leaf with the literal text as its node-type.
  "addr", "and", "as", "asm", "block", "break", "case", "cast",
  "concept", "const", "continue", "converter", "defer", "discard",
  "distinct", "div", "do", "elif", "else", "end", "enum", "except",
  "export", "finally", "for", "from", "func", "if", "import", "in",
  "include", "interface", "is", "isnot", "iterator", "let", "macro",
  "method", "mixin", "mod", "nil", "not", "notin", "object", "of",
  "or", "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr",
  "static", "template", "try", "tuple", "type", "using", "var",
  "when", "while", "xor", "yield"]

const AikenKeywordTokens = [
  "and", "as", "check", "else", "expect", "fail", "fn", "if", "is",
  "let", "or", "pub", "test", "todo", "trace", "type", "use", "validator",
  "when", "const"]

proc isNimKeyword(token: string): bool =
  for kw in NimKeywordTokens:
    if token == kw: return true
  false

proc isAikenKeyword(token: string): bool =
  for kw in AikenKeywordTokens:
    if token == kw: return true
  false

proc nimNodeKind(nodeType: string): HighlightKind =
  ## Map a tree-sitter-nim node type to a HighlightKind. Unknown
  ## semantic types fall through to `hkPlain`; the caller's `walkLeaves`
  ## already filters parents out so this only sees leaf names.
  if isNimKeyword(nodeType):
    return hkKeyword
  case nodeType
  of "comment", "block_comment", "block_documentation_comment",
     "documentation_comment":
    hkComment
  of "string_literal", "long_string_literal", "raw_string_literal",
     "char_literal", "interpreted_string_literal",
     "string_content", "generalized_string", "generalized_string_literal",
     "string", "char":
    hkString
  of "integer_literal", "float_literal", "custom_numeric_literal":
    hkNumber
  of "identifier", "accent_quoted":
    hkIdentifier
  of "operator", "binary_op", "infix_operator":
    hkOperator
  of "+", "-", "*", "/", "%", "=", "==", "!=", "<", ">", "<=", ">=",
     "and", "or", "not", "&", "|", "^", "->", "=>", "..", "...",
     "+=", "-=", "*=", "/=", ":=":
    # Anonymous operator-shaped tokens. Most overlap with keywords
    # (`and`, `or`, `not`) — those are caught above.
    hkOperator
  of "(", ")", "[", "]", "{", "}", ",", ";", ".", ":":
    hkPunctuation
  else:
    hkPlain

proc aikenNodeKind(nodeType: string): HighlightKind =
  if isAikenKeyword(nodeType):
    return hkKeyword
  case nodeType
  of "comment", "definition_comment", "module_comment",
     "doc_comment":
    hkComment
  of "string", "string_inner", "byte_string":
    hkString
  of "integer", "float", "decimal":
    hkNumber
  of "identifier", "type_identifier", "constructor":
    hkIdentifier
  of "(", ")", "[", "]", "{", "}", ",", ";", ".", ":":
    hkPunctuation
  of "+", "-", "*", "/", "==", "!=", "<", ">", "<=", ">=", "=", "->",
     "|>", "..", "::", "&&", "||":
    hkOperator
  else:
    hkPlain

# ----------------------------------------------------------------------------
# Two-language driver. The widget passes a `Language` handle (from
# `treesitter_ffi`); we dispatch on the address of the language pointer
# to pick the per-grammar mapper.
# ----------------------------------------------------------------------------

type
  GrammarKind* = enum
    gkNim
    gkAiken

proc nodeKindFor(grammar: GrammarKind; nodeType: string): HighlightKind =
  case grammar
  of gkNim:   nimNodeKind(nodeType)
  of gkAiken: aikenNodeKind(nodeType)

# ----------------------------------------------------------------------------
# Top-level entry — parse + walk.
# ----------------------------------------------------------------------------

proc tokenize*(grammar: GrammarKind; source: string): seq[Token] =
  ## Parse `source` with the requested grammar and emit the flat list
  ## of highlight tokens in source order. Spans whose mapped kind is
  ## `hkPlain` are dropped — the renderer treats unhighlighted ranges
  ## as plain text by default.
  result = @[]
  if source.len == 0: return
  let lang =
    case grammar
    of gkNim:   nimLanguage()
    of gkAiken: aikenLanguage()
  let parser = newParser()
  parser.setLanguage(lang)
  let tree = parser.parseString(source)
  let root = tree.rootNode
  for leaf in root.walkLeaves:
    let nt = leaf.nodeType
    let kind = nodeKindFor(grammar, nt)
    if kind == hkPlain: continue
    let s = leaf.startByte
    let e = leaf.endByte
    if s == e: continue  # zero-width tokens contribute nothing.
    result.add Token(startByte: s, endByte: e, kind: kind, nodeType: nt)

# ----------------------------------------------------------------------------
# Per-line projection — maps absolute byte spans into per-line
# cluster-indexed `Highlight` runs the way `widgets/textarea.nim`
# expects.
# ----------------------------------------------------------------------------

proc clusterIndexAtByte(line: string; byteOffset: int): int =
  ## Number of grapheme clusters strictly before `byteOffset` in
  ## `line`. `byteOffset == line.len` returns the cluster count.
  if byteOffset <= 0: return 0
  result = 0
  for c in widthMod.graphemeClusters(line):
    if c.start >= byteOffset: break
    inc result

proc projectToLine(line: string;
                   lineByteStart: int;
                   lineByteEnd: int;
                   tokens: seq[Token]): seq[Highlight] =
  ## Translate absolute-byte tokens into cluster-indexed highlights
  ## confined to one logical line.
  result = @[]
  for tok in tokens:
    if tok.endByte <= lineByteStart: continue
    if tok.startByte >= lineByteEnd: continue
    let lo = max(tok.startByte, lineByteStart) - lineByteStart
    let hi = min(tok.endByte, lineByteEnd) - lineByteStart
    if lo >= hi: continue
    let startCl = clusterIndexAtByte(line, lo)
    let endCl = clusterIndexAtByte(line, hi)
    if endCl <= startCl: continue
    result.add Highlight(
      startCluster: startCl, endCluster: endCl, kind: tok.kind)

proc lineByteOffsets(source: string): seq[int] =
  ## Cumulative byte offsets of each line's start within `source`.
  ## `result.len == lineCount + 1`; `result[^1] == source.len + 1` so
  ## the half-open range `[result[i], result[i+1] - 1)` covers the
  ## bytes of line `i` (excluding the trailing `\n`).
  result = @[0]
  for i, ch in source:
    if ch == '\n':
      result.add(i + 1)
  result.add(source.len + 1)

proc highlightLines*(grammar: GrammarKind; source: string):
    seq[seq[Highlight]] =
  ## Parse `source` and produce one highlight list per line.
  ## `result.len` matches the number of lines in `source` (counting
  ## `\n` separators the same way `textarea.setText` does — empty
  ## final segment included after a trailing newline).
  let tokens = tokenize(grammar, source)
  let offsets = lineByteOffsets(source)
  let lines = source.split('\n')
  result = newSeq[seq[Highlight]](lines.len)
  for i, line in lines:
    let lineStart = offsets[i]
    let lineEnd = lineStart + line.len  # excludes the trailing `\n`.
    result[i] = projectToLine(line, lineStart, lineEnd, tokens)

# ----------------------------------------------------------------------------
# Closure factory — returns a `HighlighterProc` (matching the
# `widgets/textarea.nim` plug-point) backed by a real parse of the
# captured `TextAreaWidget`'s current document text. The widget calls
# the closure once per visible logical line at render time; we cache
# the per-line table keyed on the joined-document string so successive
# per-line calls inside one render reuse a single parse.
# ----------------------------------------------------------------------------

proc newTreeSitterHighlighter*(widget: TextAreaWidget;
                               grammar: GrammarKind): HighlighterProc =
  ## Returns a closure suitable for `TextArea.setHighlighter`. The
  ## closure captures `widget` so it can read the full document on
  ## demand (the per-line callback signature alone doesn't carry that
  ## context). It re-parses lazily: on the first call after a
  ## document edit, the joined text changes, the cache is invalidated,
  ## and we run the grammar over the new bytes.
  var cachedSource: string = "\xff__never__\xff"
  var cachedLines: seq[seq[Highlight]] = @[]
  return proc(line: string; lineIndex: int): seq[Highlight] =
    discard line  # The widget passes the line text for convenience;
                  # the closure reads the joined document via the
                  # captured widget so multi-line tokens (block
                  # comments, triple-quoted strings) project correctly.
    let doc = widget.text
    if doc != cachedSource:
      cachedSource = doc
      cachedLines = highlightLines(grammar, doc)
    if lineIndex >= 0 and lineIndex < cachedLines.len:
      return cachedLines[lineIndex]
    return @[]

# ----------------------------------------------------------------------------
# Convenience: install a tree-sitter highlighter on a TextArea by name.
# Replaces the M19 stub keyword highlighter with the real grammar walk
# without changing the widget's API.
# ----------------------------------------------------------------------------

proc setTreeSitterLanguage*(widget: TextAreaWidget; grammar: GrammarKind) =
  ## Wire a real tree-sitter highlighter into `widget`. After this
  ## returns, the widget's `highlighter` closure consults the parse
  ## tree on every render. Replaces any previously-installed stub or
  ## custom highlighter.
  let langName =
    case grammar
    of gkNim:   "nim-treesitter"
    of gkAiken: "aiken-treesitter"
  widget.language = langName
  widget.setHighlighter(newTreeSitterHighlighter(widget, grammar))
