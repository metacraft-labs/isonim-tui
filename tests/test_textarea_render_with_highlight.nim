## test_textarea_render_with_highlight — M19 follow-up.
##
## Mounts a TextArea, attaches the real tree-sitter Nim highlighter
## (no stub, no mocks — the FFI compiles `parser.c` + `scanner.c` from
## `codetracer-main/libs/tree-sitter-nim/src/` into the test binary),
## sets the document content, and inspects the renderer tree to confirm
## that the cells covering the `proc` keyword carry the
## `syntax-keyword` colour style.
##
## This is the load-bearing wiring assertion: the parse tree drives
## `Highlight` runs which drive per-segment `color` styles on the
## renderer tree which the M5 cascade and M2 compositor then translate
## into per-cell SGR. We assert at the renderer-tree level so the test
## doesn't depend on the full SGR pipeline (which has its own tests).

import std/[strutils, tables]
import unittest

import isonim_tui

proc walkLeafSpans(n: TerminalNode; inheritedColor: string;
                   acc: var seq[tuple[text: string; color: string]]) =
  var col = inheritedColor
  if "color" in n.styles:
    col = n.styles["color"]
  if n.kind == tnkText and n.text.len > 0:
    acc.add (text: n.text, color: col)
  for c in n.children:
    walkLeafSpans(c, col, acc)

proc collectLeafSpans(node: TerminalNode):
    seq[tuple[text: string; color: string]] =
  ## Walk the renderer subtree below `node` collecting (text, color)
  ## pairs from every text-leaf together with its parent's `color`
  ## style attribute. Mirrors the mental model of "what would the
  ## compositor paint to the cells of this widget".
  result = @[]
  walkLeafSpans(node, "", result)

suite "M19 follow-up: textarea renders tree-sitter highlights":

  test "proc_keyword_segment_carries_keyword_color":
    let h = newTerminalTestHarness(60, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r,
        text = "proc foo(x: int): int = x + 1",
        width = 50, viewportHeight = 3,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)

    # Install the real tree-sitter Nim highlighter. This replaces the
    # M19 stub keyword highlighter that ships with the widget.
    setTreeSitterLanguage(ta, gkNim)
    # Force a re-render so the new highlighter populates the tree.
    ta.setText("proc foo(x: int): int = x + 1")

    # Walk the renderer tree under the widget, gather leaf segments.
    let segments = collectLeafSpans(ta.node)
    check segments.len > 0

    # The first non-empty content segment should be `proc` and carry
    # the keyword colour. Multiple plain segments may precede it
    # (e.g. row-edge fillers), so we scan for the literal text.
    var procColor = ""
    for seg in segments:
      if seg.text == "proc":
        procColor = seg.color
        break
    check procColor == "syntax-keyword"

  test "second_keyword_proc_in_multi_line_doc_also_styled":
    # Two proc declarations on two logical lines. Both should pick up
    # the keyword colour via the same parse.
    let h = newTerminalTestHarness(60, 8)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "",
        width = 50, viewportHeight = 5,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)
    setTreeSitterLanguage(ta, gkNim)
    ta.setText("proc a() = discard\nproc b() = discard")

    let segments = collectLeafSpans(ta.node)
    var procCount = 0
    var discardCount = 0
    for seg in segments:
      if seg.text == "proc" and seg.color == "syntax-keyword":
        inc procCount
      if seg.text == "discard" and seg.color == "syntax-keyword":
        inc discardCount
    check procCount == 2
    check discardCount == 2

  test "string_literal_carries_string_color":
    let h = newTerminalTestHarness(60, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "",
        width = 50, viewportHeight = 3,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)
    setTreeSitterLanguage(ta, gkNim)
    ta.setText("let s = \"hello\"")

    let segments = collectLeafSpans(ta.node)
    # `let` keyword should be styled.
    var letStyled = false
    var stringSeen = false
    for seg in segments:
      if seg.text == "let" and seg.color == "syntax-keyword":
        letStyled = true
      if seg.color == "syntax-string" and seg.text.contains("hello"):
        stringSeen = true
    check letStyled
    check stringSeen

  test "comment_styled_when_present":
    let h = newTerminalTestHarness(60, 6)
    var ta: TextAreaWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      ta = newTextArea(r, text = "",
        width = 50, viewportHeight = 3,
        border = bsNone)
      r.appendChild(root, ta.node)
      root)
    setTreeSitterLanguage(ta, gkNim)
    ta.setText("let x = 1  # explanation")

    let segments = collectLeafSpans(ta.node)
    var commentStyled = false
    for seg in segments:
      if seg.color == "syntax-comment":
        commentStyled = true
        break
    check commentStyled
