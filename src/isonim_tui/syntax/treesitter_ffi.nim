## syntax/treesitter_ffi.nim — Nim FFI bindings to the tree-sitter C
## API plus the bundled grammars (Nim, Aiken).
##
## Mirrors the codetracer pattern at
## `codetracer-main/libs/tree-sitter-nim/tests/nim/ts_parser_bridge.nim`.
## Public surface: `Language`, `Parser`, `Tree`, `Node`, `Point`, `Span`,
## plus the constructors / accessors that the M19 highlighter needs.
##
## The runtime (`-ltree-sitter`) is linked from the system library — see
## the `tree-sitter` package added to `flake.nix` in the same patch as
## this module. Each vendored grammar's `parser.c` (and `scanner.c`,
## when present) is compiled directly into the binary via `{.compile.}`.
##
## Charter rules:
##   * No mocks. The functions in this module call the real C parser
##     and walk a real CST. The tests in this milestone exercise the
##     full path on real Nim source bytes.
##   * Public API is value-shaped. `Tree` and `Parser` are `ref`
##     because they own a malloc'd C handle, which `=destroy` releases.
##     `Node` and `Span` are plain values.

import std/[options, os]

const
  # currentSourcePath is .../isonim-tui/src/isonim_tui/syntax/treesitter_ffi.nim
  # Walk up four levels to reach the metacraft workspace root, then
  # step sideways into the codetracer-main libs that vendor each
  # grammar's `parser.c` (+ `scanner.c`) and the bundled
  # `tree_sitter/parser.h` header.
  workspaceRoot =
    currentSourcePath().parentDir().parentDir().parentDir().parentDir().parentDir()
  nimGrammarSrcDir = workspaceRoot / "codetracer-main/libs/tree-sitter-nim/src"
  aikenGrammarSrcDir =
    workspaceRoot / "codetracer-main/libs/tree-sitter-aiken/src"

# Link against the system tree-sitter runtime. The runtime ships in the
# nix dev-shell (see flake.nix) and is also available as a vendored
# `libtree-sitter` on most distros.
{.passl: "-ltree-sitter".}

# Tell the compiler where to find each grammar's bundled `tree_sitter`
# headers. The two `parser.h` headers are byte-identical (each grammar
# vendors the same upstream copy), so `-I` for either resolves the
# `#include <tree_sitter/parser.h>` inside `parser.c`.
{.passc: "-I" & nimGrammarSrcDir.}

# Compile each grammar's C sources. The `-I` arg makes the
# grammar-local `tree_sitter/parser.h` header visible during the C
# compile of `parser.c` / `scanner.c`.
{.compile(nimGrammarSrcDir & "/parser.c", "-I" & nimGrammarSrcDir).}
{.compile(nimGrammarSrcDir & "/scanner.c", "-I" & nimGrammarSrcDir).}

{.compile(aikenGrammarSrcDir & "/parser.c", "-I" & aikenGrammarSrcDir).}

# ----------------------------------------------------------------------------
# Raw C types — opaque structs from `<tree_sitter/api.h>`. The runtime
# header is in the system include path (added by the nix `tree-sitter`
# package or by `pkg-config --cflags tree-sitter`).
# ----------------------------------------------------------------------------

type
  TSLanguage* {.importc, header: "<tree_sitter/api.h>".} = object
  TSParser* {.importc, header: "<tree_sitter/api.h>".} = object
  TSTree* {.importc, header: "<tree_sitter/api.h>".} = object
  TSNode* {.importc, header: "<tree_sitter/api.h>".} = object

  TSPoint* {.importc, header: "<tree_sitter/api.h>".} = object
    row*: uint32
    column*: uint32

  TSRange* {.importc, header: "<tree_sitter/api.h>".} = object
    startPoint*: TSPoint
    endPoint*: TSPoint
    startByte*: uint32
    endByte*: uint32

  TSSymbol* = uint16

  TSInputEncoding* {.size: sizeof(cint).} = enum
    TSInputEncodingUTF8 = 0
    TSInputEncodingUTF16 = 1

# ----------------------------------------------------------------------------
# Nim-friendly wrapper types.
# ----------------------------------------------------------------------------

type
  Language* = object
    ## Nim handle for a C `TSLanguage*`. Constant for the lifetime of
    ## the binary — the C side returns a static pointer per grammar.
    raw*: ptr TSLanguage

  Point* = object
    row*: int
    column*: int

  Span* = object
    startByte*: int
    endByte*: int
    startPoint*: Point
    endPoint*: Point

  Node* = object
    raw*: TSNode
    source*: string  ## Keeps the source bytes alive for `text()`.

  TreeObj = object
    raw: ptr TSTree
    source: string

  Tree* = ref TreeObj

  ParserObj = object
    raw: ptr TSParser

  Parser* = ref ParserObj

# ----------------------------------------------------------------------------
# Grammar entry points. Each vendored `parser.c` exports exactly one
# `tree_sitter_<name>()` symbol.
# ----------------------------------------------------------------------------

proc tree_sitter_nim(): ptr TSLanguage {.importc.}
proc tree_sitter_aiken(): ptr TSLanguage {.importc.}

# ----------------------------------------------------------------------------
# Raw runtime API (subset — what the highlighter actually uses).
# ----------------------------------------------------------------------------

proc ts_parser_new(): ptr TSParser
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_parser_delete(parser: ptr TSParser)
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_parser_set_language(parser: ptr TSParser;
                            language: ptr TSLanguage): bool
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_parser_parse_string(parser: ptr TSParser;
                            old_tree: ptr TSTree;
                            str: cstring;
                            len: uint32): ptr TSTree
  {.importc, header: "<tree_sitter/api.h>".}

proc ts_tree_delete(tree: ptr TSTree)
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_tree_root_node(tree: ptr TSTree): TSNode
  {.importc, header: "<tree_sitter/api.h>".}

proc ts_node_type(node: TSNode): cstring
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_symbol*(node: TSNode): TSSymbol
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_start_byte(node: TSNode): uint32
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_end_byte(node: TSNode): uint32
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_start_point(node: TSNode): TSPoint
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_end_point(node: TSNode): TSPoint
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_child_count(node: TSNode): uint32
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_child(node: TSNode; index: uint32): TSNode
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_named_child_count(node: TSNode): uint32
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_named_child(node: TSNode; index: uint32): TSNode
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_next_sibling(node: TSNode): TSNode
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_is_named(node: TSNode): bool
  {.importc, header: "<tree_sitter/api.h>".}
proc ts_node_is_null(node: TSNode): bool
  {.importc, header: "<tree_sitter/api.h>".}

# ----------------------------------------------------------------------------
# Destructors for owning handles.
# ----------------------------------------------------------------------------

proc `=destroy`(p: ParserObj) =
  if p.raw != nil:
    ts_parser_delete(p.raw)

proc `=destroy`(t: TreeObj) =
  if t.raw != nil:
    ts_tree_delete(t.raw)

# ----------------------------------------------------------------------------
# Language constructors. Returning `Language` (not `ptr TSLanguage`)
# keeps the surface non-pointer for callers.
# ----------------------------------------------------------------------------

proc nimLanguage*(): Language =
  ## tree-sitter-nim grammar handle. The C side returns a static
  ## pointer; the same handle may be reused across parsers.
  Language(raw: tree_sitter_nim())

proc aikenLanguage*(): Language =
  ## tree-sitter-aiken grammar handle. Used as the second-language
  ## parity demonstration alongside Nim.
  Language(raw: tree_sitter_aiken())

# ----------------------------------------------------------------------------
# Parser.
# ----------------------------------------------------------------------------

proc newParser*(): Parser =
  ## Create a fresh parser with no language set yet.
  Parser(raw: ts_parser_new())

proc setLanguage*(parser: Parser; language: Language) =
  ## Wire `language` into `parser`. Raises `ValueError` if the runtime
  ## rejects the binding (typically a tree-sitter ABI mismatch — the
  ## vendored grammars in this repo ship with the runtime).
  if not ts_parser_set_language(parser.raw, language.raw):
    raise newException(ValueError,
      "tree-sitter: failed to set language (ABI mismatch?)")

proc parseString*(parser: Parser; source: string): Tree =
  ## Parse `source` and return a fresh `Tree`. The caller keeps `source`
  ## alive for the lifetime of the tree (the wrapper holds a copy so
  ## `Node.text` works without relying on the caller).
  let raw = ts_parser_parse_string(parser.raw, nil, source.cstring,
                                   source.len.uint32)
  if raw == nil:
    raise newException(ValueError, "tree-sitter: parse_string returned NULL")
  Tree(raw: raw, source: source)

# ----------------------------------------------------------------------------
# Tree / Node accessors.
# ----------------------------------------------------------------------------

proc rootNode*(tree: Tree): Node =
  Node(raw: ts_tree_root_node(tree.raw), source: tree.source)

proc nodeType*(node: Node): string =
  $ts_node_type(node.raw)

proc isNamed*(node: Node): bool =
  ts_node_is_named(node.raw)

proc isNull*(node: Node): bool =
  ts_node_is_null(node.raw)

proc startByte*(node: Node): int =
  ts_node_start_byte(node.raw).int

proc endByte*(node: Node): int =
  ts_node_end_byte(node.raw).int

proc startPoint*(node: Node): Point =
  let p = ts_node_start_point(node.raw)
  Point(row: p.row.int, column: p.column.int)

proc endPoint*(node: Node): Point =
  let p = ts_node_end_point(node.raw)
  Point(row: p.row.int, column: p.column.int)

proc pointRange*(node: Node): tuple[startPoint, endPoint: Point] =
  (node.startPoint, node.endPoint)

proc byteRange*(node: Node): tuple[startByte, endByte: int] =
  (node.startByte, node.endByte)

proc span*(node: Node): Span =
  Span(
    startByte: node.startByte,
    endByte: node.endByte,
    startPoint: node.startPoint,
    endPoint: node.endPoint)

proc text*(node: Node): string =
  let s = node.startByte
  let e = node.endByte
  if s >= 0 and e <= node.source.len and s <= e:
    node.source[s ..< e]
  else:
    ""

proc childCount*(node: Node): int =
  ts_node_child_count(node.raw).int

proc namedChildCount*(node: Node): int =
  ts_node_named_child_count(node.raw).int

proc child*(node: Node; index: int): Node =
  Node(raw: ts_node_child(node.raw, index.uint32), source: node.source)

proc namedChild*(node: Node; index: int): Node =
  Node(raw: ts_node_named_child(node.raw, index.uint32),
       source: node.source)

proc nextSibling*(node: Node): Option[Node] =
  let s = ts_node_next_sibling(node.raw)
  if ts_node_is_null(s):
    none(Node)
  else:
    some(Node(raw: s, source: node.source))

iterator children*(node: Node): Node =
  for i in 0 ..< node.childCount:
    yield node.child(i)

iterator namedChildren*(node: Node): Node =
  for i in 0 ..< node.namedChildCount:
    yield node.namedChild(i)

iterator walk*(node: Node): Node =
  ## Pre-order traversal of all nodes (named + anonymous). The
  ## highlighter uses this to enumerate every leaf in source order.
  var stack: seq[Node] = @[node]
  while stack.len > 0:
    let cur = stack.pop()
    yield cur
    for i in countdown(cur.childCount - 1, 0):
      stack.add cur.child(i)

iterator walkLeaves*(node: Node): Node =
  ## Pre-order over leaves only — what the highlighter cares about
  ## when mapping anonymous tokens (keywords, punctuation) to colours.
  var stack: seq[Node] = @[node]
  while stack.len > 0:
    let cur = stack.pop()
    if cur.childCount == 0:
      yield cur
    else:
      for i in countdown(cur.childCount - 1, 0):
        stack.add cur.child(i)

proc `$`*(node: Node): string =
  node.nodeType & "[" & $node.startByte & ".." & $node.endByte & "]"

proc `$`*(p: Point): string =
  $p.row & ":" & $p.column

proc `$`*(span: Span): string =
  $span.startByte & ".." & $span.endByte
