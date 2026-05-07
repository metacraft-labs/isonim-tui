## test_screenbuffer_diff_empty
##
## `buf.diff(buf)` returns an empty seq, regardless of buffer size.
## The fast path is the per-row content-hash early-out — once the
## hashes match, we never recurse into per-cell comparisons.

import unittest
import std/unicode

import isonim_tui/cells

suite "ScreenBuffer.diff empty":
  test "test_unchanged_buffer_diff_returns_empty":
    let b = newScreenBuffer(80, 24)
    let regions = b.diff(b)
    check regions.len == 0

  test "test_unchanged_buffer_diff_returns_empty_large":
    let b = newScreenBuffer(200, 60)
    let regions = b.diff(b)
    check regions.len == 0

  test "test_unchanged_buffer_diff_returns_empty_tiny":
    let b = newScreenBuffer(1, 1)
    let regions = b.diff(b)
    check regions.len == 0

  test "test_two_separately_constructed_blank_buffers_match":
    let a = newScreenBuffer(80, 24)
    let b = newScreenBuffer(80, 24)
    let regions = a.diff(b)
    check regions.len == 0

  test "test_one_cell_change_produces_one_region":
    var a = newScreenBuffer(20, 5)
    var b = newScreenBuffer(20, 5)
    b.setCell(2, 7, newCell('X'))
    let regions = a.diff(b)
    check regions.len == 1
    check regions[0].row == 2
    check regions[0].col == 7
    check regions[0].width == 1
    check regions[0].cells[0].rune == Rune('X'.ord)

  test "test_changes_in_two_rows_produce_two_regions":
    var a = newScreenBuffer(20, 5)
    var b = newScreenBuffer(20, 5)
    b.setCell(0, 1, newCell('A'))
    b.setCell(3, 5, newCell('B'))
    let regions = a.diff(b)
    check regions.len == 2
    # Row 0 region first.
    check regions[0].row == 0
    check regions[0].col == 1
    check regions[1].row == 3
    check regions[1].col == 5
