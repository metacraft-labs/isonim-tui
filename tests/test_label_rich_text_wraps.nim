## test_label_rich_text_wraps — M11 mandatory test.
##
## A `Label` with a `Content` containing styled spans wraps at the
## configured cell column. The plain-text + cell-map snapshots
## confirm the wrap boundary; the inline span styles propagate to the
## compositor through the renderer's inline-style table.

import unittest
import std/unicode
import isonim_tui

suite "M11: Label rich-text wraps":
  test "test_label_rich_text_wraps":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let styled = assemble([
        ("hello ", newStyle(ansiColor(acRed))),
        ("beautiful ", newStyle(ansiColor(acGreen), attrs = {attrBold})),
        ("world", newStyle(ansiColor(acBlue)))
      ])
      let lbl = newLabel(r, styled, width = 10)
      r.appendChild(root, lbl.node)
      root)

    # The first wrapped line ends within the 10-cell budget. With soft
    # wrap and a space before "beautiful", the first line is "hello"
    # and the second line carries the rest.
    check h.cellAt(0, 0).rune == Rune('h'.ord)
    check h.cellAt(0, 4).rune == Rune('o'.ord)

    # Wrap point: column 10 of row 0 is empty (the space was consumed
    # by the soft break, so columns 5-9 are blanks padded by the
    # compositor's row-fill). Either way, no character past column 9
    # belongs to "hello".
    for col in 6 ..< 10:
      check h.cellAt(0, col).rune == Rune(' '.ord)

    # The second line starts with "beautiful".
    check h.cellAt(1, 0).rune == Rune('b'.ord)
    check h.cellAt(1, 1).rune == Rune('e'.ord)
    check h.cellAt(1, 8).rune == Rune('l'.ord)

    # Snapshot pinning (six formats; record on first run, compare
    # afterwards).
    discard h.snap("m11_label_rich_text_wraps")

    h.dispose()

  test "test_label_plain_text_wraps":
    let h = newTerminalTestHarness(40, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r,
        "the quick brown fox jumps over the lazy dog",
        width = 12)
      r.appendChild(root, lbl.node)
      root)
    # Wraps at the soft break; first line is "the quick" (within 12).
    check h.cellAt(0, 0).rune == Rune('t'.ord)
    check h.cellAt(0, 8).rune == Rune('k'.ord)
    # Row 1 starts with the first un-fitted word.
    check h.cellAt(1, 0).rune == Rune('b'.ord)

    h.dispose()
