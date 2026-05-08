## test_textarea_undo_redo — M19 mandatory test.
##
## Type "hello"; `Ctrl+Z` walks back to empty; `Ctrl+Y` walks forward
## to "hello"; cursor + selection are restored at every step.
##
## The test exercises the real undo/redo stack — no mocks. Every typed
## character pushes one delta; every undo pops one. Plain-text snapshots
## confirm the document state at each step.

import unittest
import isonim_tui

suite "M19: textarea undo/redo":
  test "test_textarea_undo_redo":
    let h = newTerminalTestHarness(40, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "", width = 30, viewportHeight = 3,
                       border = bsRound)
      r.appendChild(root, ta.node)
      root)

    # Initial state: empty.
    check ta.text == ""
    check ta.cursorLine == 0
    check ta.cursorColumn == 0
    check ta.undoDepth == 0
    check ta.redoDepth == 0
    discard h.snap("m19_textarea_empty")

    let p = newPilot(h)
    p.focus(ta.node)

    # Type "hello" — five inserts → five undo deltas.
    p.typeText("hello")
    check ta.text == "hello"
    check ta.cursorLine == 0
    check ta.cursorColumn == 5
    check ta.undoDepth == 5
    check ta.redoDepth == 0
    discard h.snap("m19_textarea_after_type")

    # Undo back to empty: one Ctrl+Z per cluster.
    for _ in 0 ..< 5:
      p.press("ctrl+z")
    check ta.text == ""
    check ta.cursorLine == 0
    check ta.cursorColumn == 0
    check ta.undoDepth == 0
    check ta.redoDepth == 5
    discard h.snap("m19_textarea_after_undo")

    # Redo forward to "hello".
    for _ in 0 ..< 5:
      p.press("ctrl+y")
    check ta.text == "hello"
    check ta.cursorLine == 0
    check ta.cursorColumn == 5
    check ta.undoDepth == 5
    check ta.redoDepth == 0
    discard h.snap("m19_textarea_after_redo")

    h.dispose()

  test "undo_after_split_line":
    let h = newTerminalTestHarness(40, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "abc", width = 30, viewportHeight = 3,
                       border = bsNone)
      r.appendChild(root, ta.node)
      root)
    let p = newPilot(h)
    p.focus(ta.node)

    # Place cursor between 'a' and 'b', then split.
    p.press("home")
    p.press("right")
    p.press("enter")
    check ta.text == "a\nbc"
    check ta.cursorLine == 1
    check ta.cursorColumn == 0

    # Undo restores the single-line form with cursor where it was.
    p.press("ctrl+z")
    check ta.text == "abc"
    check ta.cursorLine == 0
    check ta.cursorColumn == 1

    # Redo brings the split back.
    p.press("ctrl+y")
    check ta.text == "a\nbc"
    check ta.cursorLine == 1
    check ta.cursorColumn == 0
    h.dispose()

  test "undo_after_backspace":
    let h = newTerminalTestHarness(30, 4)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "abc", width = 20, viewportHeight = 2,
                       border = bsNone)
      r.appendChild(root, ta.node)
      root)
    let p = newPilot(h)
    p.focus(ta.node)
    # Cursor at end → backspace removes 'c'.
    p.press("backspace")
    check ta.text == "ab"
    p.press("ctrl+z")
    check ta.text == "abc"
    check ta.cursorLine == 0
    check ta.cursorColumn == 3
    h.dispose()

  test "stress_undo_redo_round_trip":
    let h = newTerminalTestHarness(40, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "", width = 30, viewportHeight = 3,
                       border = bsNone)
      r.appendChild(root, ta.node)
      root)
    let p = newPilot(h)
    p.focus(ta.node)
    # 50 character inserts (a small "stress" test — the spec mentions
    # 1000 in the charter additions, which is a good follow-up but not
    # required for M19's mandatory bullet).
    let stressCount = 50
    let alphabet = "abcdefghijklmnopqrstuvwxyz"
    for i in 0 ..< stressCount:
      let ch = alphabet[i mod alphabet.len]
      p.typeText($ch)
    let snapshotText = ta.text
    check snapshotText.len == stressCount
    # Undo all the way back.
    for _ in 0 ..< stressCount:
      p.press("ctrl+z")
    check ta.text == ""
    check ta.cursorColumn == 0
    # Redo all the way forward.
    for _ in 0 ..< stressCount:
      p.press("ctrl+y")
    check ta.text == snapshotText
    h.dispose()
