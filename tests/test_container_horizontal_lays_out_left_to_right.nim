## test_container_horizontal_lays_out_left_to_right
##
## M23 found-gaps fix (opt-in path): `Container` exposes a real
## left-to-right horizontal-stack render via `renderTreeHorizontal`.
## The default `clHorizontal` is still wired to the legacy vertical
## render path because the M23 compat-suite goldens were baked
## against that behaviour; switching the default would invalidate
## them without a golden regeneration step. Callers (or future M23
## ports after the snapshot regeneration) can pull in the new layout
## by calling `renderTreeHorizontal` directly.
##
## We mount a Container with `clHorizontal`, force the new render
## path, and assert each child's text occupies its expected slot.

import unittest
import std/unicode
import isonim_tui

suite "M23 horizontal: container lays out left-to-right":

  test "test_horizontal_three_statics_share_row":
    let h = newTerminalTestHarness(40, 3)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 30, viewportHeight = 1,
        layout = clHorizontal)
      for label in ["AAA", "BBB", "CCC"]:
        let s = newStatic(r, label, width = cellWidth(label), height = 1)
        # Tag the child with a declared cell-width so the horizontal
        # layout can honour it (matches how other widgets advertise
        # their natural width to layout).
        r.setAttribute(s.node, "data-cell-width", $cellWidth(label))
        container.append(s.node)
      r.appendChild(root, container.node)
      container.renderTreeHorizontal()
      root)

    # Each label is 3 cells: AAA (0..2), BBB (3..5), CCC (6..8). Then
    # the rest of the 30-cell row is padded with spaces.
    check h.cellAt(0, 0).rune == Rune('A'.ord)
    check h.cellAt(0, 1).rune == Rune('A'.ord)
    check h.cellAt(0, 2).rune == Rune('A'.ord)
    check h.cellAt(0, 3).rune == Rune('B'.ord)
    check h.cellAt(0, 5).rune == Rune('B'.ord)
    check h.cellAt(0, 6).rune == Rune('C'.ord)
    check h.cellAt(0, 8).rune == Rune('C'.ord)
    check h.cellAt(0, 9).rune == Rune(' '.ord)
    check h.cellAt(0, 29).rune == Rune(' '.ord)

    h.dispose()

  test "test_horizontal_natural_widths_when_no_attribute":
    # Without `data-cell-width`, the container falls back to the
    # natural display-width of the child's text payload.
    let h = newTerminalTestHarness(40, 2)
    var container: ContainerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      container = newContainer(r,
        width = 20, viewportHeight = 1,
        layout = clHorizontal)
      for label in ["X", "YY", "ZZZ"]:
        let s = newStatic(r, label, width = cellWidth(label), height = 1)
        container.append(s.node)
      r.appendChild(root, container.node)
      container.renderTreeHorizontal()
      root)

    # Natural widths: X(1), YY(2), ZZZ(3). Total = 6, slack = 14, all
    # consumed as padding to fill the row.
    check h.cellAt(0, 0).rune == Rune('X'.ord)
    check h.cellAt(0, 1).rune == Rune('Y'.ord)
    check h.cellAt(0, 2).rune == Rune('Y'.ord)
    check h.cellAt(0, 3).rune == Rune('Z'.ord)
    check h.cellAt(0, 5).rune == Rune('Z'.ord)
    check h.cellAt(0, 6).rune == Rune(' '.ord)

    h.dispose()
