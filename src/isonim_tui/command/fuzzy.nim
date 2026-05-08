## command/fuzzy.nim — Fuzzy matcher (M16).
##
## Port of `textual/fuzzy.py` (~225 LOC). The fuzzy matcher is the
## scoring engine behind the command palette: given a query and a
## candidate, it returns a numeric score plus the cluster offsets of
## the matching characters. A score of `0` means "no match"; higher
## scores indicate better matches.
##
## The scoring heuristic is the same one Textual ships (transcribed
## verbatim — see `score()` below). It rewards:
##
##   1. Exact / substring matches (multiplied by 1.5x or 2x).
##   2. Matches that align with word-start positions (`first_letters`).
##   3. Matches that group together into fewer contiguous runs
##      (`(matches - (groups - 1)) / matches` squared).
##
## Charter §1: every public type is a value object. A small per-matcher
## cache (`Table[(string,string), MatchResult]`) trades memory for
## stable scoring across repeated queries from the palette's incremental
## search loop. The cache is unbounded in practice — palettes finalise
## a small set of (query, candidate) pairs per session — but a manual
## `clearCache` is exposed for callers that want a deterministic LRU
## reset.
##
## The matcher only operates on **bytes**, not grapheme clusters. The
## offsets it returns are byte indices into `candidate`. Textual does
## the same — fuzzy.py uses Python's `str` which is unicode-aware
## per-codepoint but the algorithm itself is character-by-character.
## That's adequate for command labels (ASCII) and for the corpus tests.

import std/[tables, strutils, sets]

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  MatchResult* = object
    ## Result of a single (query, candidate) match attempt. `score`
    ## is the heuristic score (0 = no match). `offsets` are the byte
    ## positions in `candidate` where the query characters matched.
    score*: float64
    offsets*: seq[int]

  FuzzySearch* = ref object
    ## A reusable matcher with a per-instance cache. Mirrors
    ## `fuzzy.FuzzySearch` from Textual.
    caseSensitive*: bool
    cache*: Table[(string, string), MatchResult]

  Matcher* = ref object
    ## Higher-level wrapper: a matcher bound to a single query. The
    ## command palette holds one of these per active query so repeated
    ## scoring against the candidate set reuses the underlying cache.
    query*: string
    caseSensitive*: bool
    fuzzy*: FuzzySearch

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newFuzzySearch*(caseSensitive: bool = false): FuzzySearch =
  FuzzySearch(caseSensitive: caseSensitive,
              cache: initTable[(string, string), MatchResult]())

proc newMatcher*(query: string; caseSensitive: bool = false): Matcher =
  Matcher(query: query,
          caseSensitive: caseSensitive,
          fuzzy: newFuzzySearch(caseSensitive))

proc clearCache*(fs: FuzzySearch) =
  fs.cache.clear()

# ----------------------------------------------------------------------------
# Word-start detection (mirrors `\w+` finditer in Python)
# ----------------------------------------------------------------------------

proc isWordChar(ch: char): bool {.inline.} =
  ## Python's `\w` matches `[A-Za-z0-9_]` plus unicode letters; for the
  ## ASCII command-label corpus this ASCII subset is sufficient and
  ## byte-identical to what the corpus tests expect.
  ch in {'A'..'Z', 'a'..'z', '0'..'9', '_'}

proc firstLetters*(candidate: string): HashSet[int] =
  ## Return the set of byte positions where a "word" begins in
  ## `candidate`. A word begins after any non-word character (or at
  ## position 0). This mirrors Python's `re.finditer(r"\w+", candidate)`
  ## with `match.start()` for each match.
  result = initHashSet[int]()
  if candidate.len == 0: return
  var inWord = false
  for i, ch in candidate:
    if isWordChar(ch):
      if not inWord:
        result.incl i
        inWord = true
    else:
      inWord = false

# ----------------------------------------------------------------------------
# Scoring
# ----------------------------------------------------------------------------

proc scoreOffsets*(fs: FuzzySearch; candidate: string;
                   positions: seq[int]): float64 =
  ## The heuristic score for a (candidate, positions) pair. Transcribed
  ## from `FuzzySearch.score()` in `fuzzy.py`.
  if positions.len == 0: return 0.0
  let firstLetterSet = firstLetters(candidate)
  let offsetCount = positions.len
  var score: float64 = offsetCount.float64
  # Boost for matches that land on word-start positions.
  for p in positions:
    if p in firstLetterSet:
      score += 1.0

  # Count contiguous groups: a "group" is a run of positions where each
  # element is the previous + 1.
  var groups = 1
  var lastOffset = positions[0]
  for i in 1 ..< positions.len:
    let offset = positions[i]
    if offset != lastOffset + 1:
      groups += 1
    lastOffset = offset

  # Boost to favour fewer groups: `(matches - (groups - 1)) / matches`,
  # squared, applied multiplicatively as `1 + normalised^2`.
  let normalisedGroups =
    (offsetCount.float64 - (groups - 1).float64) / offsetCount.float64
  score *= 1.0 + (normalisedGroups * normalisedGroups)
  result = score

# ----------------------------------------------------------------------------
# Match enumeration
# ----------------------------------------------------------------------------

proc collectAllOffsets(letterPositions: seq[seq[int]];
                       queryLength: int): seq[seq[int]] =
  ## Recursively enumerate every monotonically-increasing combination
  ## of offsets where slot `i` is drawn from `letterPositions[i]`.
  ## Mirrors the inner `get_offsets` closure in `fuzzy._match`.
  result = @[]
  if queryLength == 0: return
  if letterPositions.len < queryLength: return

  proc walk(prefix: seq[int]; idx: int; acc: var seq[seq[int]]) =
    let lastVal =
      if prefix.len == 0: -1
      else: prefix[^1]
    for offset in letterPositions[idx]:
      if offset > lastVal:
        var nextPrefix = prefix
        nextPrefix.add offset
        if nextPrefix.len == queryLength:
          acc.add nextPrefix
        else:
          walk(nextPrefix, idx + 1, acc)

  walk(@[], 0, result)

iterator matchAll*(fs: FuzzySearch; query, candidate: string): MatchResult =
  ## Yield every plausible (score, offsets) pair for `(query,
  ## candidate)`. The caller's `match` proc picks the maximum-scoring
  ## entry. Mirrors `_match` in `fuzzy.py`.
  var q = query
  var c = candidate
  if not fs.caseSensitive:
    q = q.toLowerAscii
    c = c.toLowerAscii

  block matchBody:
    if q.len == 0:
      yield MatchResult(score: 0.0, offsets: @[])
      break matchBody

    # Quick exit: if the query is a substring of the candidate, that's
    # always the best fuzzy match. Score it with a 2x bonus when the
    # whole candidate is the query, 1.5x when it's a substring.
    let qFind = c.find(q)
    if qFind >= 0:
      var offsets = newSeq[int](q.len)
      for i in 0 ..< q.len:
        offsets[i] = qFind + i
      let multiplier = if c == q: 2.0 else: 1.5
      yield MatchResult(score: fs.scoreOffsets(c, offsets) * multiplier,
                        offsets: offsets)
      break matchBody

    # General case: collect every position list per query letter, then
    # enumerate all monotone combinations.
    var letterPositions: seq[seq[int]] = @[]
    var position = 0
    var anyEmpty = false
    for offset, letter in q:
      let lastIndex = c.len - offset
      var positions: seq[int] = @[]
      var index = position
      while true:
        let location = c.find(letter, index)
        if location == -1: break
        positions.add location
        index = location + 1
        if index >= lastIndex:
          break
      if positions.len == 0:
        anyEmpty = true
        break
      letterPositions.add positions
      position = positions[0] + 1

    if anyEmpty:
      yield MatchResult(score: 0.0, offsets: @[])
      break matchBody

    let combos = collectAllOffsets(letterPositions, q.len)
    if combos.len == 0:
      yield MatchResult(score: 0.0, offsets: @[])
      break matchBody

    for offsets in combos:
      yield MatchResult(score: fs.scoreOffsets(c, offsets), offsets: offsets)

proc matchOnce*(fs: FuzzySearch; query, candidate: string): MatchResult =
  ## Return the best-scoring `(score, offsets)` for `(query,
  ## candidate)`. Cached on first call. `score == 0` means no match.
  let cacheKey = (query, candidate)
  if cacheKey in fs.cache:
    return fs.cache[cacheKey]
  var best = MatchResult(score: 0.0, offsets: @[])
  for r in fs.matchAll(query, candidate):
    if r.score > best.score:
      best = r
  fs.cache[cacheKey] = best
  result = best

# ----------------------------------------------------------------------------
# Matcher (per-query wrapper) — mirrors `fuzzy.Matcher`
# ----------------------------------------------------------------------------

proc match*(m: Matcher; candidate: string): float64 =
  ## Score `candidate` against the matcher's bound query. Returns the
  ## scalar score (offsets discarded). Mirrors `Matcher.match`.
  m.fuzzy.matchOnce(m.query, candidate).score

proc matchFull*(m: Matcher; candidate: string): MatchResult =
  ## Score plus offsets — used by callers that want to highlight the
  ## matched characters.
  m.fuzzy.matchOnce(m.query, candidate)

proc highlight*(m: Matcher; candidate: string): string =
  ## Return `candidate` with matched cluster offsets surrounded by an
  ## ANSI reverse-video SGR pair. Whitespace offsets are skipped (they
  ## don't carry visible style and Textual's renderer does the same in
  ## `Matcher.highlight`).
  let r = m.matchFull(candidate)
  if r.score == 0.0 or r.offsets.len == 0:
    return candidate
  # Build output by walking bytes; insert SGR around offsets that are
  # not whitespace.
  let offsetSet = block:
    var s = initHashSet[int]()
    for o in r.offsets:
      if o < candidate.len and candidate[o] notin {' ', '\t', '\n'}:
        s.incl o
    s
  result = ""
  for i, ch in candidate:
    if i in offsetSet:
      result.add "\e[7m"
      result.add ch
      result.add "\e[27m"
    else:
      result.add ch

# ----------------------------------------------------------------------------
# Convenience procs (bare functional API)
# ----------------------------------------------------------------------------

proc fuzzyMatch*(query, candidate: string;
                 caseSensitive: bool = false): MatchResult =
  ## One-shot matcher. Builds a fresh `FuzzySearch`, returns the result.
  ## Useful when only a single query needs to be scored against a
  ## handful of candidates.
  let fs = newFuzzySearch(caseSensitive)
  fs.matchOnce(query, candidate)

proc fuzzyScore*(query, candidate: string;
                 caseSensitive: bool = false): float64 {.inline.} =
  fuzzyMatch(query, candidate, caseSensitive).score

# Note: this module operates on UTF-8 byte indices, not grapheme
# clusters. Command labels are ASCII in practice; future extension to
# grapheme-cluster matching would consume `std/unicode`'s iterator and
# return cluster-aligned offsets. Keeping the API byte-indexed today
# matches `fuzzy.py` byte-for-byte on the corpus tests.
