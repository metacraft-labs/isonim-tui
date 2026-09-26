## test_tabs_wrap_option — `TabsWidget` wraps at the ends by default and
## stops there with `wraps = false`. Driven through the pilot with real
## focus routing; no mocks.

import unittest
import isonim_tui

proc strip(): seq[Tab] =
  @[Tab(id: "a", label: "A"), Tab(id: "b", label: "B"),
    Tab(id: "c", label: "C")]

proc drive(wraps: bool): seq[int] =
  let h = newTerminalTestHarness(40, 6)
  var t: TabsWidget
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    t = newTabs(r, strip(), activeIndex = 0, wraps = wraps)
    r.appendChild(root, t.node)
    root)
  let p = newPilot(h)
  p.focus(t.node)
  p.press("left")                 # at the first tab
  result.add t.activeIndex
  p.press("end")
  p.press("right")                # at the last tab
  result.add t.activeIndex
  p.press("left")
  result.add t.activeIndex
  h.dispose()

suite "tabs wrap option":
  test "the default wraps in both directions":
    check drive(wraps = true) == @[2, 0, 2]

  test "wraps = false stops at both ends":
    check drive(wraps = false) == @[0, 2, 1]
