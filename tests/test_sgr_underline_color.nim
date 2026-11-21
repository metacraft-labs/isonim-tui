## test_sgr_underline_color
##
## An underline drawn in its own colour (CSS `text-decoration-color`), sent
## as SGR 58 in its colon form -- the extension kitty, VTE, iTerm2, WezTerm
## and xterm-compatible terminals share
## (https://sw.kovidgoyal.net/kitty/underlines/) -- and reset with SGR 59,
## which returns the underline to the foreground's colour.
##
## Two layers: the encoder (`renderSgr`) byte for byte, and the whole chain a
## view uses — a node's `underline-color` style through the compositor to the
## composited cell and the bytes the driver is sent. No mocks: the real
## compositor and the headless harness's real driver byte log.

import unittest
import std/strutils

import isonim_tui
import isonim_tui/cells
import isonim_tui/text/ansi

suite "SGR underline colour":
  test "test_sgr_underline_color_truecolor":
    let prev = newStyle(attrs = {attrUnderline})
    let curr = newStyle(attrs = {attrUnderline}, ul = rgbColor(91, 91, 214))
    check renderSgr(prev, curr) == "\x1b[58:2::91:91:214m"

  test "test_sgr_underline_color_indexed_and_ansi":
    check renderSgr(newStyle(), newStyle(ul = indexedColor(99))) == "\x1b[58:5:99m"
    check renderSgr(newStyle(), newStyle(ul = ansiColor(acBlue))) == "\x1b[58:5:4m"

  test "test_sgr_underline_color_reset_is_59":
    let prev = newStyle(attrs = {attrUnderline}, ul = rgbColor(1, 2, 3))
    let curr = newStyle(attrs = {attrUnderline})
    check renderSgr(prev, curr) == "\x1b[59m"

  test "test_sgr_underline_color_is_a_sequence_of_its_own":
    # After a truecolor foreground and background (11 parameters) the colon
    # group would take a single CSI past libvterm's 16.
    let curr = newStyle(fg = rgbColor(255, 255, 255), bg = rgbColor(60, 60, 60),
                        attrs = {attrUnderline}, ul = rgbColor(99, 102, 241))
    check renderSgr(newStyle(), curr) ==
      "\x1b[4;38;2;255;255;255;48;2;60;60;60m\x1b[58:2::99:102:241m"

  test "test_sgr_underline_color_unchanged_emits_nothing":
    let s = newStyle(fg = rgbColor(9, 9, 9), ul = rgbColor(1, 2, 3))
    check renderSgr(s, s) == ""
    check s != newStyle(fg = rgbColor(9, 9, 9))

  test "test_underline_color_reaches_the_cell_and_the_wire":
    let h = newTerminalTestHarness(20, 2)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let row = r.createElement("div")
      let marked = r.createTextNode("tab")
      r.setStyle(marked, "underline", "true")
      r.setStyle(marked, "underline-color", "#5b5bd6")
      let plain = r.createTextNode(" rest")
      r.setStyle(plain, "color", "#cccccc")
      r.appendChild(row, marked)
      r.appendChild(row, plain)
      r.appendChild(root, row)
      root)
    let underlined = h.cellAt(0, 0)
    check attrUnderline in underlined.attrs
    check underlined.ul == rgbColor(0x5b, 0x5b, 0xd6)
    check h.cellAt(0, 2).ul == rgbColor(0x5b, 0x5b, 0xd6)
    # The cells after it carry no underline colour of their own.
    check h.cellAt(0, 4).ul == defaultColor()
    let bytes = h.bytesEmitted()
    check bytes.contains("58:2::91:91:214")
    # The colour is turned back off before the plain text.
    let at = bytes.find("58:2::91:91:214")
    check bytes.find("59", at + 1) > at
    h.dispose()
