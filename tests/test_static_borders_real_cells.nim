## test_static_borders_real_cells — M11 mandatory test.
##
## A `Static` with `border: solid blue` rendered through the real
## `TerminalTestHarness` produces the expected box-drawing characters
## in the headless driver's cell buffer. The full chain is exercised:
## real renderer, real compositor, real headless driver. The
## resulting cell-map snapshot is pinned via the standard six-format
## snapshot runner.

import unittest
import std/unicode
import isonim_tui

suite "M11: Static widget borders (real cells)":
  test "test_static_borders_real_cells":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let widget = newStatic(r, "hello",
                             width = 10, height = 1,
                             border = bsSolid,
                             borderColor = "blue")
      r.appendChild(root, widget.node)
      root)

    # Top-left corner is the standard light box-drawing character ┌.
    let topLeft = h.cellAt(0, 0)
    check topLeft.rune == "┌".runeAt(0)

    # Top-right corner sits at column 11 (10 inner + 1 left edge).
    let topRight = h.cellAt(0, 11)
    check topRight.rune == "┐".runeAt(0)

    # Top horizontal segments are ─ at column 1.
    check h.cellAt(0, 1).rune == "─".runeAt(0)

    # Middle row left edge is │; the next cells render the content.
    check h.cellAt(1, 0).rune == "│".runeAt(0)
    check h.cellAt(1, 1).rune == Rune('h'.ord)
    check h.cellAt(1, 2).rune == Rune('e'.ord)
    check h.cellAt(1, 3).rune == Rune('l'.ord)
    check h.cellAt(1, 4).rune == Rune('l'.ord)
    check h.cellAt(1, 5).rune == Rune('o'.ord)
    # Padding spaces follow.
    check h.cellAt(1, 10).rune == Rune(' '.ord)
    # Right edge is │ at column 11.
    check h.cellAt(1, 11).rune == "│".runeAt(0)

    # Bottom-left corner is └ on row 2.
    check h.cellAt(2, 0).rune == "└".runeAt(0)
    check h.cellAt(2, 11).rune == "┘".runeAt(0)
    check h.cellAt(2, 1).rune == "─".runeAt(0)

    # Border cells carry the configured colour. The compositor reads
    # `color` from the row's parent box; the helper uses the named
    # `blue` ANSI palette entry.
    let topLeftFg = topLeft.fg
    check topLeftFg.kind == ckAnsi
    check topLeftFg.ansi == acBlue

    # Pin the cell map (and the other five formats).
    discard h.snap("m11_static_solid_blue")

    h.dispose()
