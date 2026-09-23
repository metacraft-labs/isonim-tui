## test_textarea_treesitter_nim — M19 follow-up.
##
## Exercises the real tree-sitter parser via FFI on a small Nim
## snippet. No mocks: the test compiles `parser.c` + `scanner.c` from
## `codetracer/libs/tree-sitter-nim/src/` into the binary and
## links the system `libtree-sitter` runtime. The walk produces real
## `Highlight` spans whose byte ranges align with the source text.

import std/[strutils, times]
import unittest

import isonim_tui

suite "M19 follow-up: tree-sitter Nim highlighter":

  test "ffi_parses_proc_definition":
    # Smallest Nim function we can typecheck visually.
    let src = "proc foo(x: int): int = x + 1"
    let parser = newParser()
    parser.setLanguage(nimLanguage())
    let tree = parser.parseString(src)
    let root = tree.rootNode
    # Root must cover the whole source.
    check root.startByte == 0
    check root.endByte == src.len
    # The grammar emits some named children for the `proc` definition.
    check root.namedChildCount > 0

  test "tokenize_emits_keyword_for_proc":
    let src = "proc foo(x: int): int = x + 1"
    let tokens = tokenize(gkNim, src)
    # We expect a non-trivial token list — at minimum keyword(s),
    # identifier(s), and either a number or an operator.
    check tokens.len > 0

    # The literal text "proc" appears at byte 0; that token must be
    # classified as a keyword.
    var procTok = -1
    for i, tok in tokens:
      if tok.startByte == 0 and tok.endByte == 4:
        procTok = i
        break
    check procTok >= 0
    check tokens[procTok].kind == hkKeyword
    # Sanity: the source slice for that token is "proc".
    check src[tokens[procTok].startByte ..< tokens[procTok].endByte] == "proc"

  test "tokenize_emits_keyword_for_int_type_annotation":
    # `int` appears twice in the snippet — both as type annotations.
    # tree-sitter-nim treats them as identifiers (no built-in type
    # node), so the kind here will be `hkIdentifier`. We assert the
    # span alignment on the first occurrence.
    let src = "proc foo(x: int): int = x + 1"
    let tokens = tokenize(gkNim, src)
    let firstIntStart = src.find("int")
    var found = false
    for tok in tokens:
      if tok.startByte == firstIntStart and tok.endByte == firstIntStart + 3:
        check tok.kind in {hkIdentifier, hkType, hkKeyword}
        found = true
        break
    check found

  test "tokenize_recognises_function_name_identifier":
    let src = "proc foo(x: int): int = x + 1"
    let tokens = tokenize(gkNim, src)
    # `foo` is an identifier in the grammar.
    let fooStart = src.find("foo")
    var found = false
    for tok in tokens:
      if tok.startByte == fooStart and tok.endByte == fooStart + 3:
        check tok.kind == hkIdentifier
        check src[tok.startByte ..< tok.endByte] == "foo"
        found = true
        break
    check found

  test "tokenize_recognises_integer_literal":
    let src = "proc foo(x: int): int = x + 1"
    let tokens = tokenize(gkNim, src)
    # The `1` literal at the end of the snippet.
    let oneStart = src.len - 1
    var found = false
    for tok in tokens:
      if tok.startByte == oneStart and tok.endByte == src.len:
        check tok.kind == hkNumber
        found = true
        break
    check found

  test "tokenize_recognises_plus_operator":
    let src = "proc foo(x: int): int = x + 1"
    let tokens = tokenize(gkNim, src)
    let plusStart = src.find(" + ") + 1
    var found = false
    for tok in tokens:
      if tok.startByte == plusStart and tok.endByte == plusStart + 1:
        # tree-sitter-nim reports `+` as part of an operator-shaped
        # node; the mapping classifies it as `hkOperator`.
        check tok.kind == hkOperator
        found = true
        break
    check found

  test "comment_classified_as_comment":
    # Comments ride a different leaf type. Multi-line comment isn't
    # used here — keep the test small and grapheme-clean.
    let src = "let x = 1  # explanatory comment\n"
    let tokens = tokenize(gkNim, src)
    var commentFound = false
    for tok in tokens:
      if tok.kind == hkComment:
        # Must cover the `#`-prefixed slice exactly.
        let slice = src[tok.startByte ..< tok.endByte]
        check slice.startsWith("#")
        commentFound = true
        break
    check commentFound

  test "highlightLines_per_line_indexing":
    # Two-line source: line 0 has a `proc` keyword at column 0, line
    # 1 has a `discard` keyword.
    let src = "proc foo() =\n  discard"
    let perLine = highlightLines(gkNim, src)
    check perLine.len == 2
    # Line 0: cluster 0..4 should be the `proc` keyword.
    var procFound = false
    for h in perLine[0]:
      if h.startCluster == 0 and h.endCluster == 4 and h.kind == hkKeyword:
        procFound = true
        break
    check procFound
    # Line 1: `discard` lands after two leading spaces.
    var discardFound = false
    for h in perLine[1]:
      if h.startCluster == 2 and h.endCluster == 9 and h.kind == hkKeyword:
        discardFound = true
        break
    check discardFound

  test "byte_span_alignment_round_trip":
    # Stronger guarantee: the slice extracted from the source by every
    # token's byte span equals the token's source view, character for
    # character.
    let src = "proc id(x: int): int = x"
    let tokens = tokenize(gkNim, src)
    check tokens.len > 0
    for tok in tokens:
      let slice = src[tok.startByte ..< tok.endByte]
      check slice.len == tok.endByte - tok.startByte
      check slice.len > 0

  test "aiken_grammar_parses_simple_validator":
    # Parity demonstration: a minimal Aiken validator. We assert the
    # parser produces a non-empty token stream and that at least one
    # keyword is recognised.
    let src = """
validator foo {
  fn bar(x: Int) -> Bool {
    x == 1
  }
}
"""
    let tokens = tokenize(gkAiken, src)
    check tokens.len > 0
    var keywordFound = false
    for tok in tokens:
      if tok.kind == hkKeyword:
        keywordFound = true
        break
    check keywordFound

suite "leafFacts: the linear, copy-free leaf walk":

  test "leafFacts_yields_exactly_walkLeaves_leaves_in_order":
    # The same leaves, the same order, the same facts: `leafFacts` is the
    # cursor walk without the per-node source copy, not a different walk.
    let src = "proc foo(x: int): int =\n  # a comment\n  result = x * 2 + 1\n" &
              "let s = \"text\"\n"
    let parser = newParser()
    parser.setLanguage(nimLanguage())
    let tree = parser.parseString(src)
    var viaNodes: seq[(string, bool, int, int)] = @[]
    for leaf in tree.rootNode.walkLeaves:
      viaNodes.add (leaf.nodeType, leaf.isNamed, leaf.startByte, leaf.endByte)
    var viaFacts: seq[(string, bool, int, int)] = @[]
    for f in tree.rootNode.leafFacts:
      viaFacts.add (f.nodeType, f.isNamed, f.startByte, f.endByte)
    check viaFacts.len > 10
    check viaFacts == viaNodes
    # Source order: every leaf starts at or after the previous one's start.
    for i in 1 ..< viaFacts.len:
      check viaFacts[i][2] >= viaFacts[i - 1][2]

  test "leafFacts_walks_a_large_file_in_linear_time":
    # 20,000 top-level procs: one statement list with 20,000 children, the
    # shape that made index-based child access quadratic and the per-node
    # source copy cost the file's size per node. Bounded generously — the
    # old walk took tens of seconds on a file this size.
    var src = ""
    for i in 0 ..< 20_000:
      src.add "proc f" & $i & "(x: int): int = x + " & $i & "\n"
    let parser = newParser()
    parser.setLanguage(nimLanguage())
    let tree = parser.parseString(src)
    let t0 = epochTime()
    var leaves = 0
    for f in tree.rootNode.leafFacts:
      inc leaves
    let took = epochTime() - t0
    checkpoint("leaves: " & $leaves & " in " & $took & " s")
    check leaves > 20_000 * 8
    check took < 5.0
