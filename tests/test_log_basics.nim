## test_log_basics — sanity checks for the Tier-3e plain-text Log
## widget. Mirrors the rich_log auto-follow contract on the simpler
## per-line surface.

import unittest
import isonim_tui

suite "M21: Log (plain text) basics":

  test "log_writeline_appends":
    let h = newTerminalTestHarness(40, 8)
    var lg: LogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      lg = newLog(r, width = 38, viewportHeight = 6)
      r.appendChild(root, lg.node)
      root)
    for i in 0 ..< 50:
      lg.writeLine("entry " & $i)
    h.flush()
    check lg.lines.len == 50
    check lg.isAtBottom
    check lg.lines[^1] == "entry 49"
    h.dispose()

  test "log_write_splits_on_newline":
    let h = newTerminalTestHarness(20, 6)
    var lg: LogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      lg = newLog(r, width = 18, viewportHeight = 4)
      let root = r.createElement("div")
      r.appendChild(root, lg.node)
      root)
    lg.write("first\nsecond\nthird")
    check lg.lines.len == 3
    check lg.lines[0] == "first"
    check lg.lines[1] == "second"
    check lg.lines[2] == "third"
    h.dispose()

  test "log_autofollow_pinned":
    let h = newTerminalTestHarness(30, 6)
    var lg: LogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      lg = newLog(r, width = 28, viewportHeight = 4)
      let root = r.createElement("div")
      r.appendChild(root, lg.node)
      root)
    for i in 0 ..< 100:
      lg.writeLine("L" & $i)
    check lg.isAtBottom
    lg.scrollHome()
    check (not lg.autoFollow)
    check lg.scrollY == 0
    for i in 100 ..< 110:
      lg.writeLine("L" & $i)
    check lg.scrollY == 0
    lg.scrollEnd()
    check lg.autoFollow
    check lg.isAtBottom
    h.dispose()

  test "log_ring_buffer":
    let h = newTerminalTestHarness(20, 6)
    var lg: LogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      lg = newLog(r, width = 18, viewportHeight = 4, maxLines = 50)
      let root = r.createElement("div")
      r.appendChild(root, lg.node)
      root)
    for i in 0 ..< 200:
      lg.writeLine("e" & $i)
    check lg.lines.len == 50
    check lg.lines[0] == "e150"
    check lg.lines[^1] == "e199"
    h.dispose()
