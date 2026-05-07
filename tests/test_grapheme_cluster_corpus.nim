## test_grapheme_cluster_corpus
##
## Run the full Unicode `GraphemeBreakTest.txt` corpus (~1100 cases for
## Unicode 16) through `graphemeClusters`. Every case must segment
## exactly the way the Unicode reference says.
##
## File format (one test per non-comment line):
##   ÷ <hex> [×÷ <hex>]* ÷    # comment
##
## Where `÷` (U+00F7) marks a break and `×` (U+00D7) marks a no-break.
## The leading and trailing `÷` are sentinels.

import unittest
import std/[strutils, os]

import isonim_tui/text/width

const FixturePath = currentSourcePath().parentDir() /
                    "fixtures/unicode/GraphemeBreakTest.txt"

type
  ParsedCase = object
    runes: seq[int32]       ## codepoint sequence
    expectedBreaks: seq[int]  ## indices into runes where breaks occur
                              ## (excluding the sentinel start/end)
    sourceLine: string
    lineNumber: int

proc parseHex(s: string): int =
  result = 0
  for ch in s:
    case ch
    of '0' .. '9': result = result * 16 + (ch.ord - '0'.ord)
    of 'a' .. 'f': result = result * 16 + (ch.ord - 'a'.ord + 10)
    of 'A' .. 'F': result = result * 16 + (ch.ord - 'A'.ord + 10)
    else: discard

proc parseCases(): seq[ParsedCase] =
  ## Parse all non-comment lines into ParsedCase records.
  result = @[]
  var lineNo = 0
  for line in lines(FixturePath):
    inc lineNo
    let body =
      if line.find('#') >= 0: line[0 ..< line.find('#')]
      else: line
    let trimmed = body.strip()
    if trimmed.len == 0: continue
    var pc: ParsedCase
    pc.sourceLine = body
    pc.lineNumber = lineNo
    # Tokens are space-separated; we look for ÷ (U+00F7 → 0xC3 0xB7),
    # × (U+00D7 → 0xC3 0x97), and hex codepoint strings.
    var idx = 0
    var pendingBreak = true  # start sentinel
    while idx < trimmed.len:
      while idx < trimmed.len and trimmed[idx] == ' ': inc idx
      if idx >= trimmed.len: break
      # Detect ÷ (0xC3 0xB7) or × (0xC3 0x97)
      if idx + 1 < trimmed.len and trimmed[idx] == '\xC3':
        let b1 = trimmed[idx + 1]
        if b1 == '\xB7':
          pendingBreak = true
          idx += 2
          continue
        elif b1 == '\x97':
          pendingBreak = false
          idx += 2
          continue
      # else hex codepoint
      var hexEnd = idx
      while hexEnd < trimmed.len and trimmed[hexEnd] != ' ':
        inc hexEnd
      let cp = parseHex(trimmed[idx ..< hexEnd])
      if pendingBreak and pc.runes.len > 0:
        pc.expectedBreaks.add(pc.runes.len)
      pc.runes.add(int32(cp))
      pendingBreak = false
      idx = hexEnd
    # The trailing sentinel break (after the last codepoint) is implicit
    # — every iteration ends after the final cluster — so we don't need
    # to record it. Filter out cases with zero runes.
    if pc.runes.len > 0:
      result.add(pc)

proc actualBreaksOf(runes: seq[int32]): seq[int] =
  ## Return the inner break indices (those between [1, runes.len)).
  for span in graphemeClusters(runes):
    if span.start != 0:
      result.add(span.start)

proc renderRunes(runes: seq[int32]): string =
  result = ""
  for i, r in runes:
    if i > 0: result.add(' ')
    result.add(toHex(r.int, 4).strip(chars = {'0'}, leading = true,
                                     trailing = false))

suite "Unicode 16 GraphemeBreakTest corpus":
  test "test_grapheme_cluster_corpus":
    let cases = parseCases()
    check cases.len > 600
    var failures = 0
    var firstFailures: seq[string] = @[]
    for pc in cases:
      let actual = actualBreaksOf(pc.runes)
      if actual != pc.expectedBreaks:
        inc failures
        if firstFailures.len < 8:
          firstFailures.add(
            "line " & $pc.lineNumber & ": runes=[" &
            renderRunes(pc.runes) & "] expected=" &
            $pc.expectedBreaks & " actual=" & $actual)
    if failures != 0:
      for msg in firstFailures: echo msg
      echo "total failures: ", failures, " / ", cases.len
    check failures == 0
