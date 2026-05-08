## test_pilot_waitFor_uses_virtual_clock
##
## A handler scheduled via `clock.schedule(callback, 100ms)` does not
## fire until `h.advance(100)` or `h.pilot.waitFor`. No real wall-clock
## sleep occurs (verified via `std/monotimes` — the test must complete
## under a few milliseconds even with a 1000-ms simulated wait).

import unittest
import isonim_tui
import isonim/core/clock
import std/[monotimes, times]

suite "M2: pilot.waitFor uses virtual clock":
  test "test_pilot_waitFor_uses_virtual_clock":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let txt = r.createTextNode("waiting")
      r.appendChild(root, txt)
      root)

    var fired = false
    let cb = proc() = fired = true
    discard h.clock.schedule(cb, 100.0)

    # Before advance: the callback hasn't fired.
    check not fired

    let p = newPilot(h)
    let wallStart = getMonoTime()
    let ok = p.waitFor(proc(): bool = fired, timeoutMs = 1000, stepMs = 10)
    let wallElapsed = (getMonoTime() - wallStart).inMilliseconds.int

    check ok
    check fired
    # Real wall time should be a few milliseconds at most — virtual
    # time advanced 100ms but no `sleep` was called. We allow generous
    # headroom for slow CI but still well under the 1000ms timeout.
    check wallElapsed < 500

    # Virtual clock has advanced.
    check h.clock.currentTime >= 100.0

    h.dispose()
