## test_layout_reflow_delta
##
## Mutating one signal that affects one node's `text` produces an
## `ArrangeDelta` with exactly that node in the `resized` set; no
## parents or siblings appear unless their layout is genuinely
## affected. Validates the reflow planner.

import unittest
import std/tables

import isonim_tui

suite "M3: layout reflow delta":
  test "test_layout_reflow_delta":
    # Build a baseline snapshot: three siblings A B C, each 10x1.
    var prevRects = initTable[int64, CellRect]()
    prevRects[1] = CellRect(col: 0, row: 0, width: 30, height: 1)  # parent
    prevRects[2] = CellRect(col: 0, row: 0, width: 10, height: 1)  # A
    prevRects[3] = CellRect(col: 10, row: 0, width: 10, height: 1) # B
    prevRects[4] = CellRect(col: 20, row: 0, width: 10, height: 1) # C

    # Mutate B (handle 3): its text now needs 12 cells. A and C
    # unchanged; parent unchanged.
    var nextRects = initTable[int64, CellRect]()
    nextRects[1] = CellRect(col: 0, row: 0, width: 30, height: 1)
    nextRects[2] = CellRect(col: 0, row: 0, width: 10, height: 1)
    nextRects[3] = CellRect(col: 10, row: 0, width: 12, height: 1)
    nextRects[4] = CellRect(col: 20, row: 0, width: 10, height: 1)

    let prev = snapshotFromTable(prevRects)
    let next = snapshotFromTable(nextRects)

    let delta = arrange(prev, next)

    # Exactly handle 3 (B) is in `resized`.
    check delta.resized == @[3'i64]
    # No siblings or parent appear.
    check delta.hidden.len == 0
    check delta.shown.len == 0
    check 1'i64 notin delta.resized
    check 2'i64 notin delta.resized
    check 4'i64 notin delta.resized
    check delta.len == 1

  test "delta detects shown and hidden nodes":
    var prevRects = initTable[int64, CellRect]()
    prevRects[1] = CellRect(col: 0, row: 0, width: 10, height: 1)
    prevRects[2] = CellRect(col: 0, row: 0, width: 5, height: 1)

    var nextRects = initTable[int64, CellRect]()
    nextRects[1] = CellRect(col: 0, row: 0, width: 10, height: 1)
    nextRects[3] = CellRect(col: 5, row: 0, width: 5, height: 1)

    let delta = arrange(snapshotFromTable(prevRects),
                        snapshotFromTable(nextRects))
    check delta.hidden == @[2'i64]
    check delta.shown == @[3'i64]
    check delta.resized.len == 0

  test "delta is empty when nothing changed":
    var rects = initTable[int64, CellRect]()
    rects[1] = CellRect(col: 0, row: 0, width: 10, height: 1)
    let snap = snapshotFromTable(rects)
    let delta = arrange(snap, snap)
    check delta.isEmpty
    check delta.len == 0
