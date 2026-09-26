## test_menu_keyboard — the `Menu` widget's keyboard contract, driven
## through the pilot (real focus routing, the harness's own driver and
## virtual clock). No mocks: `TerminalTestHarness` is the library's own
## headless host.
##
## What a menu must do that an OptionList inside a Modal does not do on its
## own: `Enter` RUNS the highlighted command AND closes, `Escape` closes
## without running anything, and focus goes back to whatever opened it.

import unittest
import isonim_tui

proc items(): seq[MenuItem] =
  @[MenuItem(id: "copy", label: "Copy"),
    MenuItem(id: "cut", label: "Cut", disabled: true),
    MenuItem(id: "paste", label: "Paste"),
    MenuItem(id: "delete", label: "Delete")]

suite "menu widget keyboard":
  test "Down skips the disabled command, Enter runs it and closes":
    let h = newTerminalTestHarness(40, 12)
    var opener: ButtonWidget
    var menu: MenuWidget
    var ran: seq[string] = @[]
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      opener = newButton(r, "Edit")
      r.appendChild(root, opener.node)
      menu = newMenu(h, items(), onActivate = proc(idx: int; id: string) =
        ran.add id)
      root)
    let p = newPilot(h)
    p.focus(opener.node)
    check not menu.isOpen
    menu.open()
    p.waitForAnimation()
    check menu.isOpen
    # The trap put focus on the command list.
    check h.focusedNode != nil
    check h.focusedNode.id == menu.node.id
    check menu.highlightedIndex == 0
    p.press("down")
    check menu.highlightedIndex == 2     # past the disabled "cut"
    p.press("enter")
    p.waitForAnimation()
    check not menu.isOpen
    check ran == @["paste"]
    check menu.lastActivated == 2
    # Focus returns to the opener.
    check h.focusedNode != nil
    check h.focusedNode.id == opener.node.id
    h.dispose()

  test "Escape closes without running anything":
    let h = newTerminalTestHarness(40, 12)
    var menu: MenuWidget
    var ran = 0
    var dismissed = 0
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      menu = newMenu(h, items(),
                     onActivate = (proc(idx: int; id: string) = inc ran),
                     onDismiss = (proc() = inc dismissed))
      root)
    let p = newPilot(h)
    menu.open()
    p.waitForAnimation()
    p.press("down")
    p.press("escape")
    p.waitForAnimation()
    check not menu.isOpen
    check ran == 0
    check dismissed == 1
    check menu.lastActivated == -1
    h.dispose()

  test "motion stops at the ends and Home / End jump":
    let h = newTerminalTestHarness(40, 12)
    var menu: MenuWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      menu = newMenu(h, items())
      root)
    let p = newPilot(h)
    menu.open()
    p.waitForAnimation()
    p.press("up")
    check menu.highlightedIndex == 0     # no wrap at the top
    p.press("end")
    check menu.highlightedIndex == 3
    p.press("down")
    check menu.highlightedIndex == 3     # no wrap at the bottom
    p.press("home")
    check menu.highlightedIndex == 0
    # Reopening starts from the first enabled command again.
    p.press("end")
    p.press("escape")
    p.waitForAnimation()
    menu.open()
    p.waitForAnimation()
    check menu.highlightedIndex == 0
    h.dispose()
