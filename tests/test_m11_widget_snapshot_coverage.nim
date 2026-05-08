## test_m11_widget_snapshot_coverage — M11 snapshot coverage.
##
## Each Tier-1a widget ships goldens (six formats) for default + a
## couple of layout states. The runner records on first invocation;
## subsequent invocations diff against the recorded goldens. This
## test exists so the M11 deliverable "each widget ships goldens"
## is single-spot enforceable.

import unittest
import isonim_tui

suite "M11: Tier-1a widget snapshot coverage":

  test "static_default_no_border":
    let h = newTerminalTestHarness(20, 3)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newStatic(r, "Hello, world", width = 18, height = 1)
      r.appendChild(root, s.node)
      root)
    discard h.snap("m11_static_default_no_border")
    h.dispose()

  test "static_solid_border":
    let h = newTerminalTestHarness(20, 4)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newStatic(r, "Hi", width = 16, height = 1,
                        border = bsSolid, borderColor = "blue")
      r.appendChild(root, s.node)
      root)
    discard h.snap("m11_static_solid_border")
    h.dispose()

  test "static_double_border":
    let h = newTerminalTestHarness(20, 4)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newStatic(r, "Hi", width = 16, height = 1,
                        border = bsDouble, borderColor = "cyan")
      r.appendChild(root, s.node)
      root)
    discard h.snap("m11_static_double_border")
    h.dispose()

  test "label_default":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r, "Just a label")
      r.appendChild(root, lbl.node)
      root)
    discard h.snap("m11_label_default")
    h.dispose()

  test "label_styled_red_bold":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r,
        styled("ALERT", newStyle(ansiColor(acRed), attrs = {attrBold})))
      r.appendChild(root, lbl.node)
      root)
    discard h.snap("m11_label_styled_red_bold")
    h.dispose()

  test "container_no_border":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let c = newContainer(r, width = 18, viewportHeight = 3)
      let l1 = newLabel(r, "row-A")
      let l2 = newLabel(r, "row-B")
      let l3 = newLabel(r, "row-C")
      c.append(l1.node)
      c.append(l2.node)
      c.append(l3.node)
      r.appendChild(root, c.node)
      root)
    discard h.snap("m11_container_no_border")
    h.dispose()

  test "container_solid_border":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let c = newContainer(r, width = 16, viewportHeight = 3,
                           border = bsSolid, borderColor = "magenta")
      let l1 = newLabel(r, "alpha")
      let l2 = newLabel(r, "beta")
      let l3 = newLabel(r, "gamma")
      c.append(l1.node)
      c.append(l2.node)
      c.append(l3.node)
      r.appendChild(root, c.node)
      root)
    discard h.snap("m11_container_solid_border")
    h.dispose()

  test "placeholder_default":
    let h = newTerminalTestHarness(20, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let ph = newPlaceholder(r, name = "Sidebar",
                              width = 14, height = 3)
      r.appendChild(root, ph.node)
      root)
    discard h.snap("m11_placeholder_default")
    h.dispose()

  test "rule_horizontal_default":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roHorizontal,
                         width = 16, style = bsSolid)
      r.appendChild(root, rule.node)
      root)
    discard h.snap("m11_rule_horizontal_default")
    h.dispose()

  test "rule_vertical_default":
    let h = newTerminalTestHarness(8, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let rule = newRule(r, orientation = roVertical,
                         height = 4, style = bsSolid)
      r.appendChild(root, rule.node)
      root)
    discard h.snap("m11_rule_vertical_default")
    h.dispose()
