## test_button_activate_with_enter — M12 mandatory test.
##
## A button with `onclick` receives an activation when `Enter` is
## pressed while focused. `h.eventLog` shows one Click event after
## the press resolves.

import unittest
import isonim_tui

suite "M12: button activate via Enter":
  test "test_button_activate_with_enter":
    let h = newTerminalTestHarness(30, 5)
    var clickCount = 0
    var btn: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      btn = newButton(r, "OK", width = 8,
                       onClick = proc() = inc clickCount)
      r.appendChild(root, btn.node)
      root)

    # No clicks before the press.
    check clickCount == 0

    let p = newPilot(h)
    p.focus(btn.node)
    check h.focusedNode != nil
    check h.focusedNode.id == btn.node.id

    p.press("enter")

    # Exactly one click registered.
    check clickCount == 1

    # Event log contains a focus event and a keydown for the press.
    let log = h.eventLog()
    check log.len > 0
    var sawFocus = false
    var sawKey = false
    for e in log:
      if e.eventType == "focus" and e.targetId == btn.node.id: sawFocus = true
      if e.eventType == "keydown" and e.targetId == btn.node.id: sawKey = true
    check sawFocus
    check sawKey

    h.dispose()

  test "space_also_activates":
    let h = newTerminalTestHarness(30, 5)
    var clickCount = 0
    var btn: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      btn = newButton(r, "Go", width = 8,
                       onClick = proc() = inc clickCount)
      r.appendChild(root, btn.node)
      root)
    let p = newPilot(h)
    p.focus(btn.node)
    p.press("space")
    check clickCount == 1
    h.dispose()

  test "disabled_button_does_not_activate":
    let h = newTerminalTestHarness(30, 5)
    var clickCount = 0
    var btn: ButtonWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      btn = newButton(r, "Off", width = 8, disabled = true,
                       onClick = proc() = inc clickCount)
      r.appendChild(root, btn.node)
      root)
    let p = newPilot(h)
    p.focus(btn.node)
    p.press("enter")
    p.press("space")
    check clickCount == 0
    h.dispose()
