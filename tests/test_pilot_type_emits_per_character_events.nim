## test_pilot_type_emits_per_character_events
##
## `h.pilot.type("hi")` produces two key events in order; the input
## widget shows "hi"; the cursor advanced two cells. The events appear
## in the harness's event log with monotonically increasing sequence
## numbers.

import unittest
import isonim_tui
import std/unicode

suite "M2: pilot.type per-character events":
  test "test_pilot_type_emits_per_character_events":
    let h = newTerminalTestHarness(20, 3)
    var typed = ""
    var label: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      label = r.createTextNode("")
      r.appendChild(root, label)
      r.addEventListener(root, "keydown",
                          proc(ev: TerminalEvent) =
        # Append the rune as a UTF-8 string.
        typed.add $Rune(ev.key.rune.int32)
        r.setTextContent(label, typed))
      root)

    let p = newPilot(h)
    p.`type`("hi")

    # Both characters arrived in order.
    check typed == "hi"
    # Visible cells reflect the input.
    check h.cellAt(0, 0).rune == Rune('h'.ord)
    check h.cellAt(0, 1).rune == Rune('i'.ord)

    # Event log has two keydown entries with monotonic sequence numbers.
    let log = h.eventLog()
    var keydownEntries: seq[EventLogEntry] = @[]
    for entry in log:
      if entry.eventType == "keydown":
        keydownEntries.add entry
    check keydownEntries.len == 2
    check keydownEntries[0].seqNumber < keydownEntries[1].seqNumber

    h.dispose()
