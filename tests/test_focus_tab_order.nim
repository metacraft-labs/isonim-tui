## test_focus_tab_order — M12 mandatory test.
##
## Three buttons in tree order: `Tab` moves focus 1→2→3→1;
## `Shift+Tab` reverses. `h.focusedNode` reflects each transition.
## A cell-map snapshot is recorded at each step.

import unittest
import isonim_tui

suite "M12: focus tab order":
  test "test_focus_tab_order":
    let h = newTerminalTestHarness(40, 5)
    var b1, b2, b3: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b1 = newButton(r, "One",   width = 8)
      b2 = newButton(r, "Two",   width = 8)
      b3 = newButton(r, "Three", width = 8)
      r.appendChild(root, b1.node)
      r.appendChild(root, b2.node)
      r.appendChild(root, b3.node)
      root)

    # Chain reflects DFS pre-order: b1, b2, b3.
    let chain = h.focusChain()
    check chain.len == 3
    check chain[0] == b1.node.id
    check chain[1] == b2.node.id
    check chain[2] == b3.node.id

    # No focus initially.
    check h.focusedNode == nil

    let p = newPilot(h)

    # Tab → first focusable.
    p.press("tab")
    check h.focusedNode != nil
    check h.focusedNode.id == b1.node.id
    discard h.snap("m12_focus_tab_step1")

    # Tab → b2.
    p.press("tab")
    check h.focusedNode.id == b2.node.id
    discard h.snap("m12_focus_tab_step2")

    # Tab → b3.
    p.press("tab")
    check h.focusedNode.id == b3.node.id
    discard h.snap("m12_focus_tab_step3")

    # Tab past last → wraps to b1.
    p.press("tab")
    check h.focusedNode.id == b1.node.id

    # Shift+Tab reverses (b1 → b3 wrap).
    p.press("shift+tab")
    check h.focusedNode.id == b3.node.id

    # Shift+Tab → b2.
    p.press("shift+tab")
    check h.focusedNode.id == b2.node.id

    # Shift+Tab → b1.
    p.press("shift+tab")
    check h.focusedNode.id == b1.node.id

    h.dispose()

  test "disabled_button_skipped_in_chain":
    let h = newTerminalTestHarness(40, 5)
    var b1, b2, b3: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      b1 = newButton(r, "One",   width = 8)
      b2 = newButton(r, "Two",   width = 8, disabled = true)
      b3 = newButton(r, "Three", width = 8)
      r.appendChild(root, b1.node)
      r.appendChild(root, b2.node)
      r.appendChild(root, b3.node)
      root)

    # Disabled b2 is not in the chain.
    let chain = h.focusChain()
    check chain.len == 2
    check chain[0] == b1.node.id
    check chain[1] == b3.node.id

    h.dispose()
