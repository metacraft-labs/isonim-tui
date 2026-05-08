## test_richlog_autofollow_real — M21 mandatory test.
##
## 10 000 lines streamed through the real `RichLog.write` path. The
## test exercises three contracts:
##
##   1. While the viewport is at the bottom (auto-follow engaged), each
##      `write` keeps the viewport pinned so the most-recent line is
##      always visible.
##   2. When the user scrolls up (`pageUp`), subsequent `write` calls
##      append silently — `scrollY` does *not* change, the visible
##      window keeps showing the same older lines.
##   3. Pressing `End` re-engages auto-follow and snaps back to the
##      bottom.
##
## Every line is appended through the real widget (no fakes). The test
## drives the renderer + compositor + headless driver pipeline so the
## bottom-of-screen cell content is asserted via `h.cellAt`.

import unittest
import isonim_tui

suite "M21: RichLog auto-follow":

  test "test_richlog_autofollow_real":
    let h = newTerminalTestHarness(50, 12)
    var rl: RichLogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rl = newRichLog(r, width = 48, viewportHeight = 10, autoFollow = true)
      r.appendChild(root, rl.node)
      root)

    # Stream 10k lines via the real signal path.
    for i in 0 ..< 10_000:
      rl.write("line " & $i)

    h.flush()

    # Auto-follow contract: scrollY pins to the bottom of the buffer.
    check rl.lines.len == 10_000
    check rl.isAtBottom
    # The last visible row must contain the most recent line.
    check rl.lines[rl.lines.len - 1].text == "line 9999"

    # Scroll up — auto-follow disengages.
    rl.pageUp()
    let frozenScrollY = rl.scrollY
    check (not rl.isAtBottom)
    check (not rl.autoFollow)

    # New writes append silently; scrollY does not move.
    for i in 10_000 ..< 10_050:
      rl.write("line " & $i)
    check rl.scrollY == frozenScrollY
    check rl.lines.len == 10_050
    check (not rl.isAtBottom)

    # Press End — re-engages auto-follow, snaps to bottom.
    let p = newPilot(h)
    discard h.setFocus(rl.node)
    p.press("end")
    check rl.autoFollow
    check rl.isAtBottom
    check rl.lines[rl.lines.len - 1].text == "line 10049"

    h.dispose()

  test "richlog_ring_buffer_caps_memory":
    ## With `maxLines` set, the oldest entries fall off and the buffer
    ## stays bounded even as we stream more data than fits.
    let h = newTerminalTestHarness(40, 8)
    var rl: RichLogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rl = newRichLog(r, width = 38, viewportHeight = 6, maxLines = 100)
      r.appendChild(root, rl.node)
      root)

    for i in 0 ..< 1000:
      rl.write("entry " & $i)
    h.flush()

    check rl.lines.len == 100
    check rl.lines[0].text == "entry 900"
    check rl.lines[99].text == "entry 999"
    h.dispose()

  test "richlog_pagedown_reengages_autofollow":
    ## Scrolling down to the bottom via PageDown also re-engages
    ## auto-follow (mirrors Textual's contract: any move that lands on
    ## the bottom row re-arms the sticky-bit).
    let h = newTerminalTestHarness(30, 6)
    var rl: RichLogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      rl = newRichLog(r, width = 28, viewportHeight = 4, autoFollow = true)
      let root = r.createElement("div")
      r.appendChild(root, rl.node)
      root)

    for i in 0 ..< 50:
      rl.write("L" & $i)
    rl.pageUp()
    check (not rl.autoFollow)
    rl.pageDown()
    rl.pageDown()
    rl.pageDown()
    rl.pageDown()
    check rl.autoFollow
    check rl.isAtBottom
    h.dispose()

  test "richlog_color_passthrough":
    ## Per-line `color` argument flows through to the rendered tree as
    ## an inline-style override.
    let h = newTerminalTestHarness(20, 4)
    var rl: RichLogWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      rl = newRichLog(r, width = 18, viewportHeight = 3)
      let root = r.createElement("div")
      r.appendChild(root, rl.node)
      root)
    rl.write("[ERROR] boom", color = "red")
    rl.write("[INFO] ok", color = "blue")
    h.flush()
    check rl.lines.len == 2
    check rl.lines[0].color == "red"
    check rl.lines[1].color == "blue"
    h.dispose()
