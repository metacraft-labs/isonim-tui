## test_sgr_minimal_transition
##
## When the only difference between two `Style` values is the
## foreground colour, `renderSgr(prev, curr)` must emit *only* the
## colour SGR — no reset, no attribute SGR.
##
## When the attribute set is unchanged but the colour changes, the
## attribute SGR must not be re-emitted (this is the "minimal
## transition" guarantee).

import unittest
import std/strutils

import isonim_tui/cells
import isonim_tui/text/ansi

suite "renderSgr minimal transition":
  test "test_sgr_only_fg_changed":
    let prev = newStyle(fg = ansiColor(acRed))
    let curr = newStyle(fg = ansiColor(acGreen))
    let s = renderSgr(prev, curr)
    # Should be the green-fg SGR only, no other params.
    check s == "\x1b[32m"
    # No reset, no attribute SGR
    check not s.contains("\x1b[0m")

  test "test_sgr_only_bg_changed":
    let prev = newStyle(bg = ansiColor(acRed))
    let curr = newStyle(bg = ansiColor(acBlue))
    let s = renderSgr(prev, curr)
    check s == "\x1b[44m"

  test "test_sgr_attrs_unchanged_color_changes":
    let prev = newStyle(fg = ansiColor(acRed), attrs = {attrBold})
    let curr = newStyle(fg = ansiColor(acGreen), attrs = {attrBold})
    let s = renderSgr(prev, curr)
    # Bold (1) must NOT be re-emitted.
    check s == "\x1b[32m"
    check not s.contains("1")

  test "test_sgr_only_attr_added":
    let prev = newStyle()
    let curr = newStyle(attrs = {attrUnderline})
    let s = renderSgr(prev, curr)
    check s == "\x1b[4m"

  test "test_sgr_only_attr_removed_uses_targeted_off_code":
    let prev = newStyle(attrs = {attrUnderline})
    let curr = newStyle()
    let s = renderSgr(prev, curr)
    # Targeted disable, not a full reset.
    check s == "\x1b[24m"
    check not s.contains("\x1b[0m")

  test "test_sgr_no_change_returns_empty":
    let s = newStyle(fg = ansiColor(acRed), attrs = {attrBold})
    check renderSgr(s, s) == ""

  test "test_reset_is_separate_proc":
    check reset() == "\x1b[0m"
