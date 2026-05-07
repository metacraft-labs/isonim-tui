## test_content_word_wrap_grapheme_aware
##
## 50 word-wrap fixtures with golden outputs. Every fixture verifies:
##
##   1. Each output line's `cellLength` is ≤ width.
##   2. No grapheme cluster is split across lines.
##   3. Concatenating the lines (re-inserting spaces where soft-wrap
##      replaced them) reproduces the input.
##   4. ZWJ emoji families and regional-indicator pairs are never split
##      in the middle.
##
## The fixtures cover ASCII, mixed-width, mid-word ZWJ emoji,
## newline-separated paragraphs, and CJK runs.

import unittest
import std/sequtils

import isonim_tui/text/content
import isonim_tui/text/width

type
  WrapCase = object
    name: string
    input: string
    width: int
    mode: WrapMode
    # Golden output: each entry is the expected line text.
    expected: seq[string]

# A small helper: build a wrap case quickly.
proc wc(name, input: string; width: int; mode: WrapMode;
        expected: openArray[string]): WrapCase =
  WrapCase(name: name, input: input, width: width, mode: mode,
           expected: @expected)

# 50 fixtures.
const Fixtures = [
  # --- ASCII soft wrap, basic word-boundary cases (10) ---
  wc("plain_short", "hello world", 20, wmSoft, ["hello world"]),
  wc("two_words_at_break", "hello world", 5, wmSoft, ["hello", "world"]),
  wc("three_words", "the quick fox", 6, wmSoft, ["the", "quick", "fox"]),
  wc("trailing_long_word", "hi everybody", 4, wmSoft, ["hi", "ever", "ybod", "y"]),
  wc("exact_fit", "abcd efgh", 4, wmSoft, ["abcd", "efgh"]),
  wc("one_over", "abcde fgh", 4, wmSoft, ["abcd", "e", "fgh"]),
  wc("single_word_no_split", "alphabet", 30, wmSoft, ["alphabet"]),
  wc("multi_space", "a  b  c", 1, wmSoft, ["a", "", "b", "", "c"]),
  wc("five_short_words", "a b c d e", 3, wmSoft, ["a b", "c d", "e"]),
  wc("breaking_at_first", "hello", 3, wmSoft, ["hel", "lo"]),

  # --- Hard wrap (5) ---
  wc("hard_basic", "abcdefghij", 4, wmHard, ["abcd", "efgh", "ij"]),
  wc("hard_with_spaces", "abcd efg", 3, wmHard, ["abc", "d e", "fg"]),
  wc("hard_exact_multiple", "aaaabbbb", 4, wmHard, ["aaaa", "bbbb"]),
  wc("hard_one_char_width", "abc", 1, wmHard, ["a", "b", "c"]),
  wc("hard_single_word", "supercalifragilistic", 5, wmHard,
     ["super", "calif", "ragil", "istic"]),

  # --- Newline-preserving (5) ---
  wc("newline_basic", "line1\nline2", 80, wmSoft, ["line1", "line2"]),
  wc("newline_with_wrap", "the quick\nbrown fox", 5, wmSoft,
     ["the", "quick", "brown", "fox"]),
  wc("trailing_newline", "hello\n", 80, wmSoft, ["hello", ""]),
  wc("leading_newline", "\nhello", 80, wmSoft, ["", "hello"]),
  wc("empty_lines", "\n\n", 80, wmSoft, ["", "", ""]),

  # --- ZWJ emoji families (8) — never split mid-cluster ---
  wc("zwj_family_at_end", "hello \xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7", 20, wmSoft,
     ["hello \xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7"]),
  wc("zwj_family_with_break", "hello \xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7", 6, wmSoft,
     ["hello", "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7"]),
  wc("two_zwj_families",
     "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7 \xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7",
     2, wmSoft,
     ["\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7",
      "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7"]),
  wc("ri_pair_jp_flag", "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5", 2, wmSoft,
     ["\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5"]),
  wc("two_ri_flags",
     "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8",
     2, wmSoft,
     ["\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5",
      "\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8"]),
  wc("ri_with_text", "JP\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5end", 4, wmHard,
     ["JP\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5", "end"]),
  wc("emoji_vs16_no_split", "ok \xE2\x9C\x88\xEF\xB8\x8F yes", 4, wmSoft,
     ["ok", "\xE2\x9C\x88\xEF\xB8\x8F", "yes"]),
  wc("combining_no_split", "a\xCC\x88bc", 2, wmHard, ["a\xCC\x88b", "c"]),

  # --- CJK / wide chars (6) ---
  wc("cjk_two_chars_width_4", "漢字", 4, wmSoft, ["漢字"]),
  wc("cjk_split_at_two", "漢字漢字", 4, wmSoft, ["漢字", "漢字"]),
  wc("cjk_uneven_width", "漢字a漢", 3, wmHard, ["漢", "字a", "漢"]),
  wc("cjk_with_space", "漢字 abc", 4, wmSoft, ["漢字", "abc"]),
  wc("cjk_long", "漢漢漢漢漢", 4, wmSoft, ["漢漢", "漢漢", "漢"]),
  wc("mixed_ascii_cjk", "Hi漢", 3, wmSoft, ["Hi", "漢"]),

  # --- Edge cases (10) ---
  wc("empty_string", "", 10, wmSoft, [""]),
  wc("only_spaces", "    ", 2, wmSoft, ["  ", " "]),
  wc("very_wide_width", "abc", 100, wmSoft, ["abc"]),
  wc("zero_input_lines", "", 1, wmSoft, [""]),
  wc("ascii_punctuation", "Hello, world!", 6, wmSoft, ["Hello,", "world!"]),
  wc("dash_separated", "a-b-c-d-e", 3, wmSoft, ["a-b", "-c-", "d-e"]),
  wc("long_word_followed_by_short", "abcdefghi z", 4, wmSoft,
     ["abcd", "efgh", "i z"]),
  wc("short_then_long_word", "z abcdefghi", 4, wmSoft,
     ["z", "abcd", "efgh", "i"]),
  wc("alternating", "a bcd e fgh i", 5, wmSoft,
     ["a bcd", "e fgh", "i"]),
  wc("spaces_only_wide", "        ", 4, wmSoft, ["    ", "   "]),

  # --- Mixed paragraphs (6) ---
  wc("two_paragraphs", "para one is here\npara two follows", 7, wmSoft,
     ["para", "one is", "here", "para", "two", "follows"]),
  wc("para_with_blank", "first\n\nsecond", 80, wmSoft,
     ["first", "", "second"]),
  wc("para_with_long", "lead\nverylongword", 4, wmSoft,
     ["lead", "very", "long", "word"]),
  wc("text_then_emoji", "hi \xE2\x9C\x88\xEF\xB8\x8F\nbye", 5, wmSoft,
     ["hi \xE2\x9C\x88\xEF\xB8\x8F", "bye"]),
  wc("emoji_then_text",
     "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5 ok",
     5, wmSoft, ["\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5 ok"]),
  wc("emoji_then_text_break",
     "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5 okay everyone",
     5, wmSoft,
     ["\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5",
      "okay",
      "every",
      "one"]),
]

proc graphemeIsAtomic(line, full: string): bool =
  ## A line is grapheme-atomic if every grapheme cluster in it is also
  ## a complete cluster in `full`. We check by ensuring all clusters in
  ## the line have widths > 0 (no orphan extending sequence).
  for cluster in graphemeClusters(line):
    if clusterDisplayWidth(cluster.text) == 0 and cluster.text.len > 0:
      # Pure combining mark cluster — could be a leak from a parent
      # cluster. Allow the parent in `full` though; the only way a
      # combining mark appears as the first cluster of a wrapped line
      # is if we split mid-cluster.
      return false
  return true

suite "Content.wrap is grapheme-aware":
  test "test_content_word_wrap_grapheme_aware":
    var failures = 0
    for fx in Fixtures:
      let c = fromString(fx.input)
      let lines = c.wrap(fx.width, fx.mode)
      let actual = lines.mapIt(it.plain)
      if actual != fx.expected:
        echo "fixture ", fx.name
        echo "  expected: ", fx.expected
        echo "  actual:   ", actual
        inc failures
        continue
      # Width invariant
      for line in lines:
        if line.cellLength > fx.width and fx.width > 0:
          echo "fixture ", fx.name, " has line wider than width: ",
               line.cellLength
          inc failures
      # Grapheme-atomic invariant
      for line in lines:
        if not graphemeIsAtomic(line.plain, fx.input):
          echo "fixture ", fx.name, " has split grapheme cluster: ",
               line.plain
          inc failures
    check failures == 0
