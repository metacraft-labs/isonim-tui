## test_compositor_idle_no_writes
##
## When no signal mutates between paints, the compositor must not call
## the driver writer at all. We mount a static tree, capture the byte
## stream length immediately after the initial paint, advance the
## virtual clock 100 times (each advance triggers a flush + paint),
## and assert the byte stream did not grow.
##
## This is M8's idle-CPU guarantee. It also exercises the `lastDirty`
## emptiness on idle paints — a no-op paint produces an empty dirty
## region set.

import unittest
import isonim_tui

suite "M8: compositor idle path":
  test "test_compositor_idle_no_writes":
    let h = newTerminalTestHarness(40, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let txt = r.createTextNode("hello world")
      r.appendChild(root, txt)
      root)

    # Immediately after mount, the driver received the initial paint.
    let baselineLen = h.bytesEmitted().len
    check baselineLen > 0

    # Advance the virtual clock 100 times without input. None of these
    # ticks should mutate any signal — so paint must short-circuit and
    # write nothing to the driver.
    for _ in 0 ..< 100:
      h.advance(1)

    let afterLen = h.bytesEmitted().len
    check afterLen == baselineLen

    # The dirty-region snapshot should be empty for the idle paints.
    check h.dirtyRegions().len == 0

    h.dispose()
