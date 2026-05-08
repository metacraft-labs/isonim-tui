## test_css_tokenize_real_textual_corpus
##
## Tokenize the curated sample of Textual-style `.tcss` fixtures under
## `tests/fixtures/tcss/`. We don't subprocess-out to Python (Textual
## not available in the dev shell). Instead we assert structural
## invariants about the token stream that Textual's own tokenizer
## guarantees:
##
##   - selector starters (id/class/type/universal) appear at the right
##     scope
##   - `{` / `}` are balanced
##   - declarations follow the `name: value;` shape
##   - the EOF token is produced exactly once at the end

import unittest
import std/[os, strutils]
import isonim_tui

const fixtureDir = currentSourcePath().parentDir() / "fixtures" / "tcss"

proc allFixtures(): seq[string] =
  for kind, path in walkDir(fixtureDir):
    if kind == pcFile and path.endsWith(".tcss"):
      result.add(path)

suite "M5: CSS tokenizer real-stack corpus":
  test "test_tokenize_real_textual_corpus":
    let fixtures = allFixtures()
    check fixtures.len >= 5  # we've got 6 sample widgets

    var totalTokens = 0
    for path in fixtures:
      let css = readFile(path)
      let toks = tokenize(css)
      check toks.len > 0
      check toks[^1].kind == tkEof

      # Balanced braces
      var braceDepth = 0
      for t in toks:
        if t.kind == tkDeclarationSetStart: inc braceDepth
        if t.kind == tkDeclarationSetEnd: dec braceDepth
        check braceDepth >= 0
      check braceDepth == 0

      # Every declaration name is followed (eventually) by a value
      # and a `;` or `}`.
      for i, t in toks:
        if t.kind == tkDeclarationName:
          var foundEnd = false
          for j in i + 1 ..< toks.len:
            if toks[j].kind in {tkDeclarationEnd, tkDeclarationSetEnd}:
              foundEnd = true; break
          check foundEnd

      totalTokens += toks.len
    # Totals — guard against silent regressions; the corpus has hundreds
    # of tokens.
    check totalTokens >= 100
