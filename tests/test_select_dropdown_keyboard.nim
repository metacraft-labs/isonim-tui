## test_select_dropdown_keyboard — M14 mandatory test.
##
## Focused Select; Enter opens a dropdown (Modal); arrows navigate;
## Enter selects; dropdown closes; focus returns to Select with the
## new value.

import unittest
import isonim_tui

suite "M14: select dropdown keyboard":
  test "test_select_dropdown_keyboard":
    let h = newTerminalTestHarness(40, 10)
    var sel: SelectWidget
    var lastChange: tuple[oldIdx, newIdx: int; newId: string] = (-9, -9, "?")
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sel = newSelect(h, [
        SelectChoice(id: "red",   label: "Red"),
        SelectChoice(id: "green", label: "Green"),
        SelectChoice(id: "blue",  label: "Blue"),
      ], width = 12,
        onChange = proc(o, n: int; id: string) =
          lastChange = (o, n, id))
      r.appendChild(root, sel.node)
      root)

    let p = newPilot(h)
    p.focus(sel.node)
    check h.focusedNode != nil
    check h.focusedNode.id == sel.node.id
    check sel.selectedIndex == -1

    # Enter opens the dropdown.
    p.press("enter")
    p.waitForAnimation()
    check sel.modal != nil
    check sel.modal.isOpen

    # The OptionList inside should be focused.
    check h.focusedNode != nil
    check h.focusedNode.id == sel.optionList.node.id
    # Highlight starts at 0.
    check sel.optionList.highlightedIndex == 0

    # Arrow-down navigates.
    p.press("down")
    check sel.optionList.highlightedIndex == 1

    # Enter selects + closes.
    p.press("enter")
    p.waitForAnimation()
    check (not sel.modal.isOpen)
    check sel.selectedIndex == 1
    check lastChange.oldIdx == -1
    check lastChange.newIdx == 1
    check lastChange.newId == "green"

    # Focus returns to the Select.
    check h.focusedNode != nil
    check h.focusedNode.id == sel.node.id

    h.dispose()

  test "select_escape_cancels":
    let h = newTerminalTestHarness(40, 10)
    var sel: SelectWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sel = newSelect(h, [
        SelectChoice(id: "a", label: "Alpha"),
        SelectChoice(id: "b", label: "Beta"),
      ], width = 10, selectedIndex = 0)
      r.appendChild(root, sel.node)
      root)

    let p = newPilot(h)
    p.focus(sel.node)
    p.press("enter")
    p.waitForAnimation()
    p.press("down")
    check sel.optionList.highlightedIndex == 1
    # Escape closes without applying.
    p.press("escape")
    p.waitForAnimation()
    check (not sel.modal.isOpen)
    check sel.selectedIndex == 0   # unchanged
    h.dispose()
