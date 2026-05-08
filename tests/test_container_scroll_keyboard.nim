## test_container_scroll_keyboard — M11 mandatory test.
##
## A `Container` taller than its viewport scrolls in response to
## `PgDn` / `PgUp` keys delivered through the real input pipeline
## (parser → driver → renderer). Cells visible in the viewport
## change accordingly; the harness's `layoutRegion` query returns
## the rectangle of the container's mounted node so a scrollbar
## column can be reserved by user code.

import unittest
import std/unicode
import isonim_tui

suite "M11: Container scrolls via keyboard":
  test "test_container_scroll_keyboard":
    let h = newTerminalTestHarness(20, 8)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 16, viewportHeight = 3,
        border = bsSolid,
        scrollable = true)

      # Add 6 labels — twice the viewport height, so PgDn must scroll.
      for i in 0 ..< 6:
        let lbl = newLabel(r, "row-" & $i)
        container.append(lbl.node)

      r.appendChild(root, container.node)
      root)

    # Initial viewport shows rows 0..2 between the borders.
    check h.cellAt(0, 0).rune == "┌".runeAt(0)
    # Inside the border on row 1 (first content row): "row-0".
    check h.cellAt(1, 0).rune == "│".runeAt(0)
    check h.cellAt(1, 1).rune == Rune('r'.ord)
    check h.cellAt(1, 2).rune == Rune('o'.ord)
    check h.cellAt(1, 3).rune == Rune('w'.ord)
    check h.cellAt(1, 4).rune == Rune('-'.ord)
    check h.cellAt(1, 5).rune == Rune('0'.ord)

    # Focus the container so keys route to it.
    let p = newPilot(h)
    p.focus(container.node)

    # Send PgDn through the real pilot path. Step is `viewportHeight - 1`
    # so the scroll offset advances by 2.
    p.press("pagedown")

    # After scrolling, the first content row shows row-2.
    check h.cellAt(1, 1).rune == Rune('r'.ord)
    check h.cellAt(1, 5).rune == Rune('2'.ord)

    # Layout region of the container reflects its full reserved
    # rectangle (top border + viewport rows + bottom border = 5).
    let region = h.layoutRegion(container.node)
    check region.row == 0
    check region.col == 0
    # The row reserved for the scrollbar is column `width + 1` of the
    # container — the right-edge border glyph occupies it. M11
    # reserves it via the bordered shell; explicit scrollbar styling
    # ships in M14.

    # PgUp returns the scroll position.
    p.press("pageup")
    check h.cellAt(1, 1).rune == Rune('r'.ord)
    check h.cellAt(1, 5).rune == Rune('0'.ord)

    h.dispose()

  test "test_container_pagedown_clamps_at_end":
    let h = newTerminalTestHarness(20, 6)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 14, viewportHeight = 2,
        border = bsSolid, scrollable = true)
      for i in 0 ..< 4:
        let lbl = newLabel(r, "L" & $i)
        container.append(lbl.node)
      r.appendChild(root, container.node)
      root)

    let p = newPilot(h)
    p.focus(container.node)

    # PgDn 5 times — far past the end. Scroll position must clamp to
    # `len - viewportHeight = 4 - 2 = 2`, so the visible window is
    # always rows 2..3 and the rune at row 1 col 1 is "L2".
    for _ in 0 ..< 5:
      p.press("pagedown")
    check h.cellAt(1, 1).rune == Rune('L'.ord)
    check h.cellAt(1, 2).rune == Rune('2'.ord)

    h.dispose()
