## test_strip_diff
##
## Minimal-region diff tests for `Strip.diff(other)`:
##   * One cell differing → exactly one region of width 1.
##   * Five contiguous cells differing → one merged region of width 5.
##   * Two non-contiguous regions → two separate regions.
##
## All cells / strips are constructed via real public APIs from
## `cells.nim`. No mocks.

import unittest
import std/unicode

import isonim_tui/cells

proc stripFromString(s: string): Strip =
  var cells = newSeq[Cell](s.len)
  for i, ch in s:
    cells[i] = newCell(ch)
  newStrip(cells)

suite "Strip.diff minimal regions":
  test "test_strip_diff_single_cell":
    let a = stripFromString("hello")
    let b = stripFromString("hellp")  # last char differs
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].col == 4
    check regions[0].width == 1
    check regions[0].cells.len == 1
    check regions[0].cells[0].rune == Rune('p'.ord)

  test "test_strip_diff_five_contiguous":
    # Cols 1..5 differ ("zzzzz" vs "abcde"); cols 0 and 6 agree.
    let a = stripFromString("Xabcdef")
    let b = stripFromString("Xzzzzzf")
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].col == 1
    check regions[0].width == 5

  test "test_strip_diff_two_disjoint_regions":
    # Differ at index 1 and again at index 4 (with index 2,3 same):
    let a = stripFromString("abcde")
    let b = stripFromString("aXcdY")
    let regions = a.diff(b)
    check regions.len == 2
    check regions[0].col == 1
    check regions[0].width == 1
    check regions[0].cells[0].rune == Rune('X'.ord)
    check regions[1].col == 4
    check regions[1].width == 1
    check regions[1].cells[0].rune == Rune('Y'.ord)

  test "test_strip_diff_identical_returns_empty":
    let a = stripFromString("identical")
    let b = stripFromString("identical")
    let regions = a.diff(b)
    check regions.len == 0

  test "test_strip_diff_completely_different":
    let a = stripFromString("aaaaa")
    let b = stripFromString("bbbbb")
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].col == 0
    check regions[0].width == 5

  test "test_strip_caches_displayWidth_and_hash":
    let s = stripFromString("hello")
    check s.displayWidth == 5
    check s.contentHash != 0  # near-zero collision odds for any non-empty string

    # Two strips with same content have same hash.
    let s2 = stripFromString("hello")
    check s.contentHash == s2.contentHash
    check s == s2

  test "test_strip_diff_growing":
    # Right strip is longer than left; diff includes a trailing region
    # for the new columns.
    let a = stripFromString("abc")
    let b = stripFromString("abcXY")
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].col == 3
    check regions[0].width == 2

  test "test_strip_diff_shrinking":
    # Right strip is shorter; diff fills the freed columns with blanks.
    let a = stripFromString("abcde")
    let b = stripFromString("abc")
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].col == 3
    check regions[0].width == 2
    for cell in regions[0].cells:
      check cell == spaceCell()
