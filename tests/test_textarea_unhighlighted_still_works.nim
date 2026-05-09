## test_textarea_unhighlighted_still_works — M19 follow-up
## back-compat assertion.
##
## After the M19 follow-up wires tree-sitter into the TextArea, every
## existing API call that creates a TextArea **without** any language
## or highlighter must still produce the same plain-text widget. No
## colour styles should appear on body cells; cursor / scrolling /
## undo behaviour stays unchanged.
##
## This test reuses the original M19 test surface (no language passed,
## no `setLanguage` call) and asserts on the rendered tree directly.

import std/tables
import unittest

import isonim_tui

proc walkLeafColors(n: TerminalNode; inheritedColor: string;
                    acc: var seq[tuple[text: string; color: string]]) =
  var col = inheritedColor
  if "color" in n.styles:
    col = n.styles["color"]
  if n.kind == tnkText and n.text.len > 0:
    acc.add (text: n.text, color: col)
  for c in n.children:
    walkLeafColors(c, col, acc)

proc collectLeafSpans(node: TerminalNode):
    seq[tuple[text: string; color: string]] =
  result = @[]
  walkLeafColors(node, "", result)

suite "M19 follow-up: textarea without a language stays plain":

  test "no_color_styles_on_body_cells":
    # Same surface as the existing M19 textarea tests — no
    # `language` argument, no `setLanguage` call.
    let h = newTerminalTestHarness(40, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r,
        text = "proc foo() = discard",
        width = 30, viewportHeight = 3,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)

    # Highlighter must still be nil — no implicit tree-sitter wiring.
    check ta.highlighter == nil

    let segments = collectLeafSpans(ta.node)
    # Every body segment should carry no colour. (Border-row segments
    # may carry a border colour; this widget mounted with bsNone has
    # no border to colour.)
    for seg in segments:
      check seg.color == ""

  test "set_language_clear_returns_to_plain":
    # Edit-time path: install a tree-sitter highlighter, then clear it
    # via the existing `setLanguage("")` hook. Cells should revert to
    # uncoloured.
    let h = newTerminalTestHarness(40, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "proc foo() = discard",
        width = 30, viewportHeight = 3,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)
    setTreeSitterLanguage(ta, gkNim)
    # Confirm at least one keyword cell got coloured.
    block:
      let segs = collectLeafSpans(ta.node)
      var anyKeyword = false
      for seg in segs:
        if seg.color == "syntax-keyword":
          anyKeyword = true
          break
      check anyKeyword

    # Clear the highlighter.
    ta.setLanguage("")
    check ta.highlighter == nil
    # Force a re-render with the cleared highlighter.
    ta.setText(ta.text)

    let segs = collectLeafSpans(ta.node)
    for seg in segs:
      check seg.color == ""

  test "edits_do_not_break_widget_when_no_highlighter":
    # An end-to-end smoke through a few mutations confirms that the
    # existing `renderTree` path still works for unhighlighted
    # documents after the M19 follow-up changes (e.g. the cursor-row
    # branch was rewritten to use `emitHighlightedRow` with reverse).
    let h = newTerminalTestHarness(30, 4)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "abc", width = 20, viewportHeight = 2,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)
    let p = newPilot(h)
    p.focus(ta.node)
    p.press("end")
    p.typeText("d")
    check ta.text == "abcd"
    p.press("backspace")
    check ta.text == "abc"
    p.press("ctrl+z")
    check ta.text == "abcd"
    h.dispose()
