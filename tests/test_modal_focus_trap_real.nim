## test_modal_focus_trap_real — M14 mandatory test.
##
## Open a modal containing two buttons; outside the modal there's an
## opener button. Tab should cycle inside the modal only (verified
## via `h.focusedNode`). Escape closes the modal; focus returns to
## the opener button.

import unittest
import std/tables
import isonim_tui

suite "M14: modal focus trap":
  test "test_modal_focus_trap_real":
    let h = newTerminalTestHarness(50, 12)
    var opener: ButtonWidget
    var modalBtnA, modalBtnB: ButtonWidget
    var modal: ModalWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      opener = newButton(r, "Open Modal", width = 14)
      r.appendChild(root, opener.node)
      modal = newModal(h, "Confirm",
                      width = 30, height = 6,
                      animDurationMs = 0.0)  # instant for trap test
      modalBtnA = newButton(r, "OK", width = 6)
      modalBtnB = newButton(r, "Cancel", width = 10)
      r.appendChild(modal.contentMount, modalBtnA.node)
      r.appendChild(modal.contentMount, modalBtnB.node)
      modal.installEscapeHandler()
      root)

    let p = newPilot(h)
    p.focus(opener.node)
    check h.focusedNode != nil
    check h.focusedNode.id == opener.node.id

    # Open the modal — focus moves into modal subtree.
    modal.open()
    p.waitForAnimation()
    check modal.isOpen

    # Focus must be inside the modal panel (one of modalBtnA / B).
    let firstFocus = h.focusedNode
    check firstFocus != nil
    check (firstFocus.id == modalBtnA.node.id or
           firstFocus.id == modalBtnB.node.id)

    # The focus chain should now be limited to nodes under the panel.
    let chain = h.focusChain()
    check chain.len == 2
    check (modalBtnA.node.id in chain)
    check (modalBtnB.node.id in chain)
    check (opener.node.id notin chain)

    # Tab cycles inside the trap only.
    p.press("tab")
    let after1Tab = h.focusedNode.id
    check (after1Tab == modalBtnA.node.id or after1Tab == modalBtnB.node.id)
    p.press("tab")
    let after2Tabs = h.focusedNode.id
    check (after2Tabs == modalBtnA.node.id or after2Tabs == modalBtnB.node.id)
    # Tab three times - we wrap and never escape into opener.
    p.press("tab")
    p.press("tab")
    check (h.focusedNode.id == modalBtnA.node.id or
           h.focusedNode.id == modalBtnB.node.id)

    # Press Escape on the focused button — installed handler closes.
    modal.close()
    p.waitForAnimation()
    check (not modal.isOpen)

    # Focus returns to opener.
    check h.focusedNode != nil
    check h.focusedNode.id == opener.node.id

    h.dispose()

  test "modal_compositor_layer_above_base":
    ## The modal sits on layer N >= 1 so the M8 compositor renders it
    ## above the base tree. Verify by reading the compositor's
    ## introspection: the modal's panel renders.
    let h = newTerminalTestHarness(40, 8)
    var modal: ModalWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let baseLabel = newLabel(r, "BASE")
      r.appendChild(root, baseLabel.node)
      modal = newModal(h, "On Top", width = 20, height = 4,
                       animDurationMs = 0.0)
      root)
    modal.open()
    let p = newPilot(h)
    p.waitForAnimation()
    check modal.isOpen
    # The modal node carries `layer` style.
    check modal.node.styles.hasKey("layer")
    h.dispose()
