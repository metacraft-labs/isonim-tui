## test_content_basics
##
## Covers the M1 Content deliverables that aren't otherwise gated:
## `cellLength`, `append`, `assemble`, `lines`, `truncate`, `rstrip`,
## `highlight`, and the toAnsi rendering pipeline. Real types only —
## no mocks.

import unittest
import std/[sequtils, strutils]

import isonim_tui/cells
import isonim_tui/text/content
import isonim_tui/text/ansi

suite "Content M1 API":
  test "test_content_cell_length_grapheme_aware":
    let c = fromString("hi 漢")
    check c.cellLength == 5  # 'h' + 'i' + ' ' + 漢(2)

  test "test_content_append_string":
    let a = fromString("hello")
    let b = a.append(" world")
    check b.plain == "hello world"

  test "test_content_append_content_shifts_spans":
    let a = styled("alpha", newStyle(fg = ansiColor(acRed)))
    let b = styled("beta", newStyle(fg = ansiColor(acBlue)))
    let c = a.append(b)
    check c.plain == "alphabeta"
    check c.spans.len == 2
    check c.spans[0].start == 0
    check c.spans[0].stop == 5
    check c.spans[1].start == 5
    check c.spans[1].stop == 9

  test "test_content_assemble":
    let c = assemble([
      ("hello ", newStyle(fg = ansiColor(acRed))),
      ("world", newStyle(fg = ansiColor(acGreen)))
    ])
    check c.plain == "hello world"
    check c.spans.len == 2
    check c.spans[0].style.fg == ansiColor(acRed)
    check c.spans[1].style.fg == ansiColor(acGreen)

  test "test_content_lines_basic":
    let c = fromString("alpha\nbeta\ngamma")
    let ls = c.lines.mapIt(it.plain)
    check ls == @["alpha", "beta", "gamma"]

  test "test_content_lines_preserve_spans":
    let c = assemble([
      ("alpha\n", newStyle(fg = ansiColor(acRed))),
      ("beta", newStyle(fg = ansiColor(acGreen)))
    ])
    let ls = c.lines
    check ls.len == 2
    check ls[0].plain == "alpha"
    check ls[0].spans.len == 1
    check ls[0].spans[0].style.fg == ansiColor(acRed)
    check ls[1].plain == "beta"
    check ls[1].spans.len == 1
    check ls[1].spans[0].style.fg == ansiColor(acGreen)

  test "test_content_truncate_pad":
    let c = fromString("hi")
    let padded = c.truncate(5)
    check padded.plain == "hi   "

  test "test_content_truncate_crop":
    let c = fromString("hello world")
    let cropped = c.truncate(5)
    check cropped.plain == "hello"

  test "test_content_truncate_ellipsis":
    let c = fromString("hello world")
    let cropped = c.truncate(5, ellipsis = true)
    check cropped.cellLength == 5
    check cropped.plain.endsWith("\xe2\x80\xa6")  # "…"

  test "test_content_rstrip_default_whitespace":
    let c = fromString("hello   ")
    let r = c.rstrip
    check r.plain == "hello"

  test "test_content_rstrip_clips_spans":
    let c = assemble([
      ("hello", newStyle(fg = ansiColor(acRed))),
      ("   ", newStyle(fg = ansiColor(acBlue)))
    ])
    let r = c.rstrip
    check r.plain == "hello"
    # The blue span over the whitespace must be removed.
    for sp in r.spans:
      check sp.start < 5
      check sp.stop <= 5

  test "test_content_highlight_basic":
    let c = fromString("hello world hello")
    let h = c.highlight(r"hello", newStyle(fg = ansiColor(acRed)))
    # Two matches → two added spans.
    check h.spans.len >= 2
    var matchCount = 0
    for sp in h.spans:
      if sp.style.fg == ansiColor(acRed): inc matchCount
    check matchCount == 2

  test "test_content_to_ansi":
    let c = assemble([
      ("hello", newStyle(fg = ansiColor(acRed))),
      (" ", defaultStyle()),
      ("world", newStyle(fg = ansiColor(acBlue)))
    ])
    let s = c.toAnsi
    check s.contains("\x1b[31m")  # red fg
    check s.contains("\x1b[34m")  # blue fg
    check s.contains("hello")
    check s.contains("world")

  test "test_content_value_semantics":
    # Mutating a copy must not affect the original.
    let a = fromString("alpha")
    let b = a.append("beta")
    check a.plain == "alpha"
    check b.plain == "alphabeta"
