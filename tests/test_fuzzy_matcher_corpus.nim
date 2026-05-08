## test_fuzzy_matcher_corpus — M16 mandatory test.
##
## Drive the fuzzy matcher through 200 (query, candidate, expected_score)
## tuples sourced from `tests/fixtures/fuzzy_corpus.json`. The fixture
## was generated against Textual's reference `fuzzy.FuzzySearch`
## implementation (see `tests/fixtures/fuzzy_corpus.json` and the
## generator notes in M16's milestone bullet) — every entry is a
## byte-for-byte score from Python `textual/fuzzy.py`.
##
## Charter §1: every public type the matcher exposes is a value object
## (`MatchResult`); the `FuzzySearch` cache is the only `ref`. The test
## constructs a fresh `FuzzySearch` per case so cache reuse can't mask
## bugs in the scorer itself.

import unittest
import std/[json, math]

import isonim_tui/command/fuzzy

suite "M16: fuzzy matcher corpus":
  test "test_fuzzy_matcher_corpus":
    let corpus = parseFile("tests/fixtures/fuzzy_corpus.json")
    check corpus.len == 200
    var passed = 0
    var failed = 0
    var firstFailures: seq[string] = @[]
    for entry in corpus:
      let q = entry[0].getStr
      let c = entry[1].getStr
      let expected = entry[2].getFloat
      let got = fuzzyScore(q, c)
      if abs(got - expected) <= 1e-6:
        passed += 1
      else:
        failed += 1
        if firstFailures.len < 10:
          firstFailures.add "q=" & q & " c=" & c &
                            " expected=" & $expected & " got=" & $got
    if failed > 0:
      for f in firstFailures: echo f
    check failed == 0
    check passed == 200

  test "fuzzy_matcher_substring_quick_exit":
    ## Quick-exit branch: when the query is a substring of the
    ## candidate, the score is the substring run scored once and
    ## multiplied by 1.5x (or 2x when the whole candidate equals the
    ## query). Mirrors the early `query in candidate` branch in
    ## `_match`.
    let exact = fuzzyScore("quit", "quit")
    let substring = fuzzyScore("quit", "Quit Application")
    check exact > substring  # 2x vs 1.5x bonus
    check exact > 0.0
    check substring > 0.0

  test "fuzzy_matcher_no_match_returns_zero":
    check fuzzyScore("xz", "abcdefg") == 0.0
    check fuzzyScore("hi", "hello") == 0.0  # no `i` in hello

  test "fuzzy_matcher_case_insensitive_default":
    ## Default case-insensitive scoring matches lowercase + uppercase
    ## queries identically.
    let lower = fuzzyScore("th", "Switch theme")
    let upper = fuzzyScore("TH", "Switch theme")
    let mixed = fuzzyScore("Th", "Switch theme")
    check lower == upper
    check lower == mixed

  test "fuzzy_matcher_case_sensitive_path":
    ## When `caseSensitive = true`, capitalisation differences become
    ## non-matches.
    check fuzzyScore("th", "THEME", caseSensitive = true) == 0.0
    check fuzzyScore("TH", "THEME", caseSensitive = true) > 0.0

  test "fuzzy_matcher_offsets_are_byte_indices":
    ## Offsets are byte indices into the (lower-cased) candidate. We
    ## verify by re-extracting the matched characters and checking
    ## they form the query.
    let r = fuzzyMatch("th", "Switch theme")
    check r.offsets.len == 2
    let lowered = "switch theme"
    check lowered[r.offsets[0]] == 't'
    check lowered[r.offsets[1]] == 'h'

  test "fuzzy_matcher_cache_returns_same_result":
    ## Repeat scoring caches the result; the cached lookup is byte-
    ## identical to a fresh compute.
    let fs = newFuzzySearch()
    let r1 = fs.matchOnce("th", "Switch theme")
    let r2 = fs.matchOnce("th", "Switch theme")
    check r1.score == r2.score
    check r1.offsets == r2.offsets

  test "fuzzy_matcher_highlight_wraps_matches":
    ## `highlight` returns `candidate` with the matched bytes wrapped
    ## in ANSI reverse-video SGR codes. Whitespace offsets are skipped.
    let m = newMatcher("th")
    let h = m.highlight("Switch theme")
    # Two non-whitespace matches → two reverse-video pairs.
    var count = 0
    var i = 0
    while i < h.len - 1:
      if h[i] == '\e' and h[i + 1] == '[':
        if i + 3 < h.len and h[i + 2] == '7' and h[i + 3] == 'm':
          count += 1
      inc i
    check count == 2
