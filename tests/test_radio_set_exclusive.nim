## test_radio_set_exclusive — M12 mandatory test.
##
## Three radio buttons in a set: selecting one deselects the others.
## `h.eventLog` confirms one selection event with old + new id.

import unittest
import isonim_tui

suite "M12: radio set exclusive selection":
  test "test_radio_set_exclusive":
    let h = newTerminalTestHarness(40, 5)
    var rs: RadioSetWidget
    var rb1, rb2, rb3: RadioButtonWidget
    var lastOld = -1
    var lastNew = -1
    var lastValue = ""
    var changeCount = 0
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rs = newRadioSet(r,
        onChange = proc(o, n: int; v: string) =
          lastOld = o
          lastNew = n
          lastValue = v
          inc changeCount)
      rb1 = newRadioButton(r, "Apple",  value = "a")
      rb2 = newRadioButton(r, "Banana", value = "b")
      rb3 = newRadioButton(r, "Cherry", value = "c")
      rs.add(rb1)
      rs.add(rb2)
      rs.add(rb3)
      r.appendChild(root, rs.node)
      root)

    # Nothing selected initially.
    check rs.selectedIndex == -1

    let p = newPilot(h)
    p.focus(rb1.node)

    # Press space → selects rb1.
    p.press("space")
    check rb1.selected == true
    check rb2.selected == false
    check rb3.selected == false
    check rs.selectedIndex == 0
    check rs.selectedValue == "a"
    check changeCount == 1
    check lastOld == 0
    check lastNew == rb1.node.id
    check lastValue == "a"

    # Move focus to rb2; activate.
    p.focus(rb2.node)
    p.press("space")
    check rb1.selected == false
    check rb2.selected == true
    check rb3.selected == false
    check rs.selectedValue == "b"
    check changeCount == 2
    check lastOld == rb1.node.id
    check lastNew == rb2.node.id

    # Move to rb3.
    p.focus(rb3.node)
    p.press("space")
    check rb3.selected == true
    check rb2.selected == false
    check rs.selectedValue == "c"
    check changeCount == 3

    h.dispose()

  test "radio_set_select_index_programmatic":
    let h = newTerminalTestHarness(40, 5)
    var rs: RadioSetWidget
    var rb1, rb2: RadioButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rs = newRadioSet(r)
      rb1 = newRadioButton(r, "X")
      rb2 = newRadioButton(r, "Y")
      rs.add(rb1)
      rs.add(rb2)
      r.appendChild(root, rs.node)
      root)
    rs.selectIndex(1)
    check rb1.selected == false
    check rb2.selected == true
    h.dispose()
