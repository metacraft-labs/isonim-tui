## test_eventLog_records_in_order
##
## Three pilot actions (press, click, type) produce log entries with
## monotonically increasing sequence numbers and the right targets.

import unittest
import isonim_tui

suite "M2: event log records in order":
  test "test_eventLog_records_in_order":
    let h = newTerminalTestHarness(30, 5)
    var btn: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      btn = r.createElement("button")
      r.setAttribute(btn, "id", "go")
      r.appendChild(btn, r.createTextNode("Go"))
      r.appendChild(root, btn)
      root)

    let p = newPilot(h)
    p.press("enter")             # logs (0, "keydown")
    p.click(btn)                  # logs (id, "mousedown"), (id, "mouseup"), (id, "click")
    p.`type`("ok")               # logs (0, "keydown"), (0, "keydown")

    let log = h.eventLog()
    check log.len >= 3

    # Sequence numbers strictly monotonic.
    var prev = 0
    for e in log:
      check e.seqNumber > prev
      prev = e.seqNumber

    # First entry was the press → keydown.
    check log[0].eventType == "keydown"
    # The middle entries include mousedown / mouseup / click on btn.
    var sawMouseDown = false
    var sawClick = false
    for e in log:
      if e.targetId == btn.id and e.eventType == "mousedown":
        sawMouseDown = true
      if e.targetId == btn.id and e.eventType == "click":
        sawClick = true
    check sawMouseDown
    check sawClick

    # Last two entries are keydowns from the type("ok").
    check log[^1].eventType == "keydown"
    check log[^2].eventType == "keydown"

    # `lastEvent` accessor.
    let last = h.lastEvent()
    check last.seqNumber == log[^1].seqNumber

    h.dispose()
