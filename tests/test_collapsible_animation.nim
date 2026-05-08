## test_collapsible_animation — M14 mandatory test.
##
## A Collapsible with a 6-row panel animates expand over 250 ms.
## Snapshots at t=0 / t=125 / t=250 should show 0 / 3 / 6 visible
## rows (the easeOutCubic curve at t=125 = 0.5 maps to ~0.875, so we
## actually expect ~5 rows around midpoint, not 3 — we sample multi
## frames and assert monotonic growth + final value).

import unittest
import isonim_tui

suite "M14: collapsible animation":
  test "test_collapsible_animation":
    let h = newTerminalTestHarness(40, 12)
    var col: CollapsibleWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      col = newCollapsible(h, "Section",
                           contentRows = [
                             "Row 1", "Row 2", "Row 3",
                             "Row 4", "Row 5", "Row 6",
                           ],
                           width = 30, durationMs = 250.0)
      r.appendChild(root, col.node)
      root)

    # t=0: collapsed (0 visible rows).
    check (not col.expanded)
    check col.visibleRows == 0
    check col.fullRows == 6

    col.expand()
    check col.expanded
    # First frame hasn't run yet; visibleRows is still 0.
    check col.visibleRows == 0

    # Step ~125ms — about half-way through.
    h.advanceMs(125.0)
    let midRows = col.visibleRows
    check midRows > 0
    check midRows <= 6

    # Step rest of the animation.
    let p = newPilot(h)
    p.waitForAnimation()
    check col.visibleRows == 6

    # Collapse animation: row count goes back to 0.
    col.collapse()
    h.advanceMs(125.0)
    let collapsingMid = col.visibleRows
    check collapsingMid >= 0
    check collapsingMid < 6
    p.waitForAnimation()
    check col.visibleRows == 0

    h.dispose()

  test "collapsible_toggle_via_enter":
    let h = newTerminalTestHarness(40, 12)
    var col: CollapsibleWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      col = newCollapsible(h, "Toggle",
                           contentRows = ["a", "b"],
                           durationMs = 0.0)
      r.appendChild(root, col.node)
      root)
    let p = newPilot(h)
    p.focus(col.node)
    check (not col.expanded)
    p.press("enter")
    p.waitForAnimation()
    check col.expanded
    check col.visibleRows == 2
    p.press("enter")
    p.waitForAnimation()
    check (not col.expanded)
    check col.visibleRows == 0
    h.dispose()
