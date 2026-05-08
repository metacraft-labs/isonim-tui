## test_header_footer_welcome — Tier-3e app-chrome widgets.
##
## Smoke tests that the header / footer / welcome widgets mount through
## the full renderer + compositor + driver pipeline and produce visible
## cells matching the configured payload.

import unittest
import std/strutils
import isonim_tui

suite "M21: Header / Footer / Welcome chrome":

  test "header_renders_title_and_icon":
    let h = newTerminalTestHarness(40, 4)
    var hd: HeaderWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      hd = newHeader(r, title = "MyApp", subtitle = "subtitle",
                     width = 40, tall = false,
                     backgroundColor = "blue", color = "white")
      let root = r.createElement("div")
      r.appendChild(root, hd.node)
      root)
    h.flush()
    # The title text appears somewhere on row 0.
    var row = ""
    for col in 0 ..< 40:
      row.add char(h.cellAt(0, col).rune.int32 and 0xFF)
    check "MyApp" in row
    h.dispose()

  test "header_setters_repaint":
    let h = newTerminalTestHarness(40, 4)
    var hd: HeaderWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      hd = newHeader(r, title = "Old", width = 40)
      let root = r.createElement("div")
      r.appendChild(root, hd.node)
      root)
    hd.setTitle("New")
    hd.setSubtitle("Sub")
    hd.setIcon("*")
    hd.setClock("12:34")
    hd.setTall(true)
    h.flush()
    check hd.title == "New"
    check hd.subtitle == "Sub"
    check hd.tall
    h.dispose()

  test "footer_renders_key_bindings":
    let h = newTerminalTestHarness(60, 3)
    var fw: FooterWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      fw = newFooter(r, bindings = [
                       FooterBinding(key: "q", description: "Quit"),
                       FooterBinding(key: "?", description: "Help")],
                     width = 60)
      let root = r.createElement("div")
      r.appendChild(root, fw.node)
      root)
    h.flush()
    var row = ""
    for col in 0 ..< 60:
      row.add char(h.cellAt(0, col).rune.int32 and 0xFF)
    check "[q]" in row
    check "Quit" in row
    check "[?]" in row
    check "Help" in row
    h.dispose()

  test "footer_mutators":
    let h = newTerminalTestHarness(40, 3)
    var fw: FooterWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      fw = newFooter(r, width = 40)
      let root = r.createElement("div")
      r.appendChild(root, fw.node)
      root)
    fw.addBinding(FooterBinding(key: "a", description: "Add"))
    fw.addBinding(FooterBinding(key: "d", description: "Delete"))
    check fw.bindings.len == 2
    fw.setCompact(false)
    fw.clearBindings()
    check fw.bindings.len == 0
    fw.setBindings([FooterBinding(key: "x", description: "Close")])
    check fw.bindings.len == 1
    h.dispose()

  test "welcome_renders_title_and_action":
    let h = newTerminalTestHarness(60, 14)
    var ww: WelcomeWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      ww = newWelcome(r, title = "Hello",
                      body = ["A line", "Another line"],
                      width = 60, height = 14, actionLabel = "OK")
      let root = r.createElement("div")
      r.appendChild(root, ww.node)
      root)
    h.flush()
    # Title appears on row 1 (row 0 is the top border).
    var titleRow = ""
    for col in 0 ..< 60:
      titleRow.add char(h.cellAt(1, col).rune.int32 and 0xFF)
    check "Hello" in titleRow
    # Action label appears on the row above the bottom border.
    var actionRow = ""
    for col in 0 ..< 60:
      actionRow.add char(h.cellAt(12, col).rune.int32 and 0xFF)
    check "OK" in actionRow
    h.dispose()

  test "welcome_default_body":
    let h = newTerminalTestHarness(60, 14)
    var ww: WelcomeWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      ww = newWelcome(r, width = 60, height = 14)
      let root = r.createElement("div")
      r.appendChild(root, ww.node)
      root)
    check ww.title == "Welcome"
    check ww.body.len == DefaultWelcomeBody.len
    ww.setTitle("Hi")
    ww.setBody(["Custom body"])
    ww.setActionLabel("Dismiss")
    check ww.title == "Hi"
    check ww.body.len == 1
    check ww.actionLabel == "Dismiss"
    h.dispose()
