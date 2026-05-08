## test_input_selection_keybindings — M13 mandatory test.
##
## Shift+Home selects to start; Shift+End selects to end; Ctrl+A is the
## "go-to-start" binding (Textual semantics) but Ctrl+Shift+A selects
## all. Cell-map shows highlighted cells (attrReverse on the input row)
## when selection is active.

import unittest
import isonim_tui

proc inputRowHasReverse(h: TerminalTestHarness; row: int;
                        startCol, endCol: int): bool =
  ## Returns true when at least one cell in the column range has
  ## `attrReverse` set in its attribute set.
  for c in startCol .. endCol:
    if attrReverse in h.cellAt(row, c).attrs:
      return true
  return false

suite "M13: input selection keybindings":
  test "test_input_selection_keybindings":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "hello", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)

    # Initially no selection: cursor and anchor coincide.
    check inp.hasSelection == false
    check inp.cursorPos == 5

    # Shift+Home selects from cursor (5) back to start (0).
    p.press("shift+home")
    check inp.hasSelection == true
    check inp.selection.cursor == 0
    check inp.selection.anchor == 5
    # Cell-map shows highlighted (attrReverse) cells in the input row.
    check inputRowHasReverse(h, 1, 1, 11)

    # Move cursor (without shift) collapses the selection.
    p.press("end")
    check inp.hasSelection == false
    # No reverse cells now.
    check inputRowHasReverse(h, 1, 1, 11) == false

    # Shift+End from start = same outcome (anchor at 0, cursor at 5).
    p.press("home")
    p.press("shift+end")
    check inp.hasSelection == true
    check inp.selection.anchor == 0
    check inp.selection.cursor == 5
    check inputRowHasReverse(h, 1, 1, 11)

    h.dispose()

  test "ctrl_shift_a_select_all":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "world", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    p.press("ctrl+shift+a")
    check inp.hasSelection == true
    check inp.selection.anchor == 0
    check inp.selection.cursor == 5
    check inputRowHasReverse(h, 1, 1, 11)
    h.dispose()

  test "shift_left_extends_selection_one_cluster":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "abc", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    check inp.cursorPos == 3
    p.press("shift+left")
    check inp.hasSelection == true
    check inp.selection.cursor == 2
    check inp.selection.anchor == 3
    p.press("shift+left")
    check inp.selection.cursor == 1
    check inp.selection.anchor == 3
    h.dispose()

  test "typing_replaces_active_selection":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "hello", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    p.press("ctrl+shift+a")
    check inp.hasSelection == true
    p.typeText("Z")
    check inp.value == "Z"
    check inp.cursorPos == 1
    check inp.hasSelection == false
    h.dispose()
