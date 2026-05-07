## test_ambiguous_width_default_narrow
##
## Ambiguous-width characters (UAX #11 EAW=A) default to width 1
## (matches Textual). Calling `setAmbiguousWidth(awWide)` flips them to
## width 2 — and crucially, must not break other glyphs:
##
##   * ASCII width stays 1
##   * EAW=W (Wide) characters stay 2
##   * EAW=Na/N stay 1
##   * Only EAW=A characters change.

import unittest
import std/unicode

import isonim_tui/text/width

# A small set of canonical EAW=A code points:
const AmbiguousSamples = [
  Rune(0x00A1),  # ¡ INVERTED EXCLAMATION MARK
  Rune(0x00A4),  # ¤ CURRENCY SIGN
  Rune(0x00A7),  # § SECTION SIGN
  Rune(0x00B0),  # ° DEGREE SIGN
  Rune(0x2010),  # ‐ HYPHEN
  Rune(0x2013),  # – EN DASH
  Rune(0x2014),  # — EM DASH
  Rune(0x2018),  # ' LEFT SINGLE QUOTATION MARK
]

suite "ambiguous-width policy":
  setup:
    setAmbiguousWidth(awNarrow)  # restore default for each test

  test "test_default_is_narrow":
    check getAmbiguousWidth() == awNarrow
    for r in AmbiguousSamples:
      check displayWidth(r) == 1

  test "test_aw_wide_flips_ambiguous_only":
    setAmbiguousWidth(awWide)
    for r in AmbiguousSamples:
      check displayWidth(r) == 2

    # ASCII stays 1.
    check displayWidth(Rune('A'.ord)) == 1
    check displayWidth(Rune('z'.ord)) == 1

    # Wide CJK stays 2.
    check displayWidth(Rune(0x6F22)) == 2  # 漢

    # Halfwidth katakana (EAW=H) stays 1.
    check displayWidth(Rune(0xFF65)) == 1

  test "test_string_width_respects_ambiguous_setting":
    setAmbiguousWidth(awNarrow)
    let s = "\xC2\xA7\xC2\xA7\xC2\xA7"  # three §
    check displayWidth(s) == 3
    setAmbiguousWidth(awWide)
    check displayWidth(s) == 6

  test "test_aw_setting_is_per_thread":
    # The threadvar default for a freshly entered thread / context is
    # awNarrow.
    setAmbiguousWidth(awNarrow)
    check getAmbiguousWidth() == awNarrow
    setAmbiguousWidth(awWide)
    check getAmbiguousWidth() == awWide
    setAmbiguousWidth(awNarrow)  # reset for following tests
