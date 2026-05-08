## test_m12_widget_snapshot_coverage — M12 snapshot coverage.
##
## Each Tier-1b widget ships goldens (six formats) for default +
## `:focus` + `:hover` + `:disabled` states. The runner records on
## first invocation; subsequent invocations diff against the recorded
## goldens. `:hover` and `:focus` states are surfaced via the
## harness's hovered/focused id fields so the annotated-svg snapshot
## reflects the state.

import unittest
import isonim_tui

suite "M12: Tier-1b widget snapshot coverage":

  # ----- Button -----

  test "button_default":
    let h = newTerminalTestHarness(20, 4)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let b = newButton(r, "OK", width = 8)
      r.appendChild(root, b.node)
      root)
    discard h.snap("m12_button_default")
    h.dispose()

  test "button_focus":
    let h = newTerminalTestHarness(20, 4)
    var b: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b = newButton(r, "OK", width = 8)
      r.appendChild(root, b.node)
      root)
    let p = newPilot(h)
    p.focus(b.node)
    discard h.snap("m12_button_focus")
    h.dispose()

  test "button_hover":
    let h = newTerminalTestHarness(20, 4)
    var b: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b = newButton(r, "OK", width = 8)
      r.appendChild(root, b.node)
      root)
    let p = newPilot(h)
    p.hover(b.node)
    discard h.snap("m12_button_hover")
    h.dispose()

  test "button_disabled":
    let h = newTerminalTestHarness(20, 4)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let b = newButton(r, "OK", width = 8, disabled = true)
      r.appendChild(root, b.node)
      root)
    discard h.snap("m12_button_disabled")
    h.dispose()

  # ----- Switch -----

  test "switch_default":
    let h = newTerminalTestHarness(10, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newSwitch(r, value = false)
      r.appendChild(root, s.node)
      root)
    discard h.snap("m12_switch_default")
    h.dispose()

  test "switch_focus":
    let h = newTerminalTestHarness(10, 2)
    var s: SwitchWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      s = newSwitch(r, value = false)
      r.appendChild(root, s.node)
      root)
    let p = newPilot(h)
    p.focus(s.node)
    discard h.snap("m12_switch_focus")
    h.dispose()

  test "switch_hover":
    let h = newTerminalTestHarness(10, 2)
    var s: SwitchWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      s = newSwitch(r, value = true)
      r.appendChild(root, s.node)
      root)
    let p = newPilot(h)
    p.hover(s.node)
    discard h.snap("m12_switch_hover")
    h.dispose()

  test "switch_disabled":
    let h = newTerminalTestHarness(10, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newSwitch(r, value = false, disabled = true)
      r.appendChild(root, s.node)
      root)
    discard h.snap("m12_switch_disabled")
    h.dispose()

  # ----- Checkbox -----

  test "checkbox_default":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let c = newCheckbox(r, "Enabled", value = false)
      r.appendChild(root, c.node)
      root)
    discard h.snap("m12_checkbox_default")
    h.dispose()

  test "checkbox_focus":
    let h = newTerminalTestHarness(20, 2)
    var c: CheckboxWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      c = newCheckbox(r, "Enabled", value = true)
      r.appendChild(root, c.node)
      root)
    let p = newPilot(h)
    p.focus(c.node)
    discard h.snap("m12_checkbox_focus")
    h.dispose()

  test "checkbox_hover":
    let h = newTerminalTestHarness(20, 2)
    var c: CheckboxWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      c = newCheckbox(r, "Enabled", value = false)
      r.appendChild(root, c.node)
      root)
    let p = newPilot(h)
    p.hover(c.node)
    discard h.snap("m12_checkbox_hover")
    h.dispose()

  test "checkbox_disabled":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let c = newCheckbox(r, "Enabled", value = false, disabled = true)
      r.appendChild(root, c.node)
      root)
    discard h.snap("m12_checkbox_disabled")
    h.dispose()

  # ----- RadioButton -----

  test "radiobutton_default":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rb = newRadioButton(r, "Apple")
      r.appendChild(root, rb.node)
      root)
    discard h.snap("m12_radiobutton_default")
    h.dispose()

  test "radiobutton_focus":
    let h = newTerminalTestHarness(20, 2)
    var rb: RadioButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rb = newRadioButton(r, "Apple")
      r.appendChild(root, rb.node)
      root)
    let p = newPilot(h)
    p.focus(rb.node)
    discard h.snap("m12_radiobutton_focus")
    h.dispose()

  test "radiobutton_hover":
    let h = newTerminalTestHarness(20, 2)
    var rb: RadioButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rb = newRadioButton(r, "Apple", selected = true)
      r.appendChild(root, rb.node)
      root)
    let p = newPilot(h)
    p.hover(rb.node)
    discard h.snap("m12_radiobutton_hover")
    h.dispose()

  test "radiobutton_disabled":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rb = newRadioButton(r, "Apple", disabled = true)
      r.appendChild(root, rb.node)
      root)
    discard h.snap("m12_radiobutton_disabled")
    h.dispose()

  # ----- RadioSet -----

  test "radioset_default":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rs = newRadioSet(r)
      rs.add(newRadioButton(r, "A"))
      rs.add(newRadioButton(r, "B", selected = true))
      rs.add(newRadioButton(r, "C"))
      r.appendChild(root, rs.node)
      root)
    discard h.snap("m12_radioset_default")
    h.dispose()
