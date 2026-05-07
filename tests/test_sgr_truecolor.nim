## test_sgr_truecolor
##
## Verifies the 24-bit RGB encoding is byte-exact:
##   `Color.rgb(255, 100, 50)` → `"\x1b[38;2;255;100;50m"`
##
## Also covers the indexed (256-color) and ANSI 0-15 paths via direct
## SGR comparisons.

import unittest

import isonim_tui/cells
import isonim_tui/text/ansi

suite "SGR truecolor / indexed / ansi encoding":
  test "test_sgr_truecolor_fg":
    let prev = newStyle()
    let curr = newStyle(fg = rgbColor(255, 100, 50))
    check renderSgr(prev, curr) == "\x1b[38;2;255;100;50m"

  test "test_sgr_truecolor_bg":
    let prev = newStyle()
    let curr = newStyle(bg = rgbColor(0, 128, 255))
    check renderSgr(prev, curr) == "\x1b[48;2;0;128;255m"

  test "test_sgr_indexed_256_color":
    let prev = newStyle()
    let curr = newStyle(fg = indexedColor(208))
    check renderSgr(prev, curr) == "\x1b[38;5;208m"

  test "test_sgr_ansi_basic_8":
    let prev = newStyle()
    let curr = newStyle(fg = ansiColor(acRed))
    check renderSgr(prev, curr) == "\x1b[31m"

  test "test_sgr_ansi_bright":
    let prev = newStyle()
    let curr = newStyle(fg = ansiColor(acBrightYellow))
    check renderSgr(prev, curr) == "\x1b[93m"

  test "test_sgr_default_color_after_color":
    let prev = newStyle(fg = ansiColor(acRed))
    let curr = newStyle()  # default fg
    check renderSgr(prev, curr) == "\x1b[39m"

  test "test_sgr_color_builder_helper":
    # `colorB.rgb(...)` is the same as `rgbColor(...)`.
    let c1 = colorB.rgb(10, 20, 30)
    let c2 = rgbColor(10, 20, 30)
    check c1 == c2
