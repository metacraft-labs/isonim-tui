## test_grapheme_width_emoji_zwj
##
## Verifies the grapheme-cluster iterator + display-width pipeline on
## the cases the milestone calls out specifically:
##
##   * The ZWJ family "👨‍👩‍👧" (man-ZWJ-woman-ZWJ-girl):
##       - 5 codepoints
##       - 1 grapheme cluster
##       - displayWidth == 2
##
##   * The Japanese flag "🇯🇵" (regional-indicator J + regional-indicator P):
##       - 2 codepoints
##       - 1 grapheme cluster
##       - displayWidth == 2
##
##   * Plain wide CJK glyphs: each is one cluster, width 2.
##   * Variation selectors do not introduce extra clusters.

import unittest
import std/unicode

import isonim_tui/text/width

suite "grapheme + width on emoji / RI / ZWJ":
  test "test_zwj_family_one_cluster_width_two":
    let family = "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7"
    # = U+1F468 ZWJ U+1F469 ZWJ U+1F467 (man + ZWJ + woman + ZWJ + girl)
    var runeCount = 0
    for _ in runes(family): inc runeCount
    check runeCount == 5

    var clusterCount = 0
    for _ in graphemeClusters(family): inc clusterCount
    check clusterCount == 1

    check displayWidth(family) == 2
    check graphemeClusterCount(family) == 1

  test "test_regional_indicator_pair_width_two":
    let jpFlag = "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5"  # U+1F1EF U+1F1F5
    var runeCount = 0
    for _ in runes(jpFlag): inc runeCount
    check runeCount == 2

    var clusterCount = 0
    for _ in graphemeClusters(jpFlag): inc clusterCount
    check clusterCount == 1
    check displayWidth(jpFlag) == 2

  test "test_two_flags_two_clusters":
    # 4 RIs in a row → 2 clusters (US flag + Japan flag).
    let twoFlags = "\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8" &  # US (U+1F1FA U+1F1F8)
                   "\xF0\x9F\x87\xAF\xF0\x9F\x87\xB5"    # JP
    check graphemeClusterCount(twoFlags) == 2
    check displayWidth(twoFlags) == 4

  test "test_wide_cjk_single_cluster":
    let han = "漢"  # U+6F22, EAW W
    check graphemeClusterCount(han) == 1
    check displayWidth(han) == 2

  test "test_combining_mark_no_extra_cluster":
    let aWithDiaeresis = "a\xCC\x88"  # 'a' + U+0308 COMBINING DIAERESIS
    check graphemeClusterCount(aWithDiaeresis) == 1
    check displayWidth(aWithDiaeresis) == 1

  test "test_emoji_vs16_promotes_width":
    # Airplane is EAW Neutral but Extended_Pictographic; with VS16 it's
    # rendered as emoji (2 cells) per most modern terminals/Textual.
    let plane = "\xE2\x9C\x88"           # U+2708 — narrow on its own
    let planeEmoji = "\xE2\x9C\x88\xEF\xB8\x8F"   # + VS16
    check graphemeClusterCount(plane) == 1
    check graphemeClusterCount(planeEmoji) == 1
    check displayWidth(plane) == 1
    check displayWidth(planeEmoji) == 2
