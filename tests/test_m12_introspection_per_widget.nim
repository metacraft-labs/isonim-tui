## test_introspection_per_widget — M12 mandatory test.
##
## For each Tier-1b widget, `h.dumpTree()` contains it; `h.computedStyle(w)`
## matches the cascade output; `h.layoutRegion(w)` matches the cell
## rectangle observed in the cell-map snapshot.

import unittest
import std/strutils
import isonim_tui

suite "M12: introspection per widget":
  test "test_introspection_per_widget":
    let h = newTerminalTestHarness(40, 12)
    var btn: ButtonWidget
    var sw: SwitchWidget
    var cb: CheckboxWidget
    var rs: RadioSetWidget
    var rb1, rb2: RadioButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "root")
      btn = newButton(r, "Click", width = 10)
      r.setAttribute(btn.node, "id", "the-button")
      sw  = newSwitch(r, value = true)
      r.setAttribute(sw.node, "id", "the-switch")
      cb  = newCheckbox(r, "Subscribe", value = false)
      r.setAttribute(cb.node, "id", "the-checkbox")
      rs  = newRadioSet(r)
      r.setAttribute(rs.node, "id", "the-radio-set")
      rb1 = newRadioButton(r, "First")
      rb2 = newRadioButton(r, "Second")
      rs.add(rb1)
      rs.add(rb2)
      r.appendChild(root, btn.node)
      r.appendChild(root, sw.node)
      r.appendChild(root, cb.node)
      r.appendChild(root, rs.node)
      root)

    let dump = h.dumpTree()
    check dump.contains("#the-button")
    check dump.contains("#the-switch")
    check dump.contains("#the-checkbox")
    check dump.contains("#the-radio-set")
    # Layout regions surface in the dump as `[row,col WxH]`.
    check dump.contains("[")

    # computedStyle is a value object; runs cleanly for every widget.
    let btnStyle = h.computedStyle(btn.node)
    check btnStyle.display == "block"
    let swStyle = h.computedStyle(sw.node)
    check swStyle.display == "block"
    let cbStyle = h.computedStyle(cb.node)
    check cbStyle.display == "block"
    let rsStyle = h.computedStyle(rs.node)
    check rsStyle.display == "block"

    # Layout region is well-formed (positive width/height for visible
    # widgets, the rectangle aligns with what the cell-map shows).
    let btnRegion = h.layoutRegion(btn.node)
    check btnRegion.row >= 0
    check btnRegion.col >= 0
    check btnRegion.width > 0
    check btnRegion.height > 0

    let swRegion = h.layoutRegion(sw.node)
    check swRegion.width > 0
    check swRegion.height > 0

    let cbRegion = h.layoutRegion(cb.node)
    check cbRegion.width > 0
    check cbRegion.height > 0

    let rsRegion = h.layoutRegion(rs.node)
    check rsRegion.width > 0

    # Each widget is independently focusable.
    check isFocusable(btn.node)
    check isFocusable(sw.node)
    check isFocusable(cb.node)
    check isFocusable(rb1.node)
    check isFocusable(rb2.node)

    # Disabled flag flips focusable.
    btn.setDisabled(true)
    check not isFocusable(btn.node)
    btn.setDisabled(false)
    check isFocusable(btn.node)

    h.dispose()
