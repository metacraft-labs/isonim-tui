## test_input_grapheme_cursor — M13 mandatory test.
##
## Typing "👨‍👩‍👧" (5 codepoints, 1 grapheme cluster, width 2) advances
## the cursor by 2 cells, not 5. Backspace removes the entire cluster.

import unittest
import isonim_tui

const family = "\xf0\x9f\x91\xa8" &  # 👨 (1F468)
               "\xe2\x80\x8d" &      # ZWJ
               "\xf0\x9f\x91\xa9" &  # 👩 (1F469)
               "\xe2\x80\x8d" &      # ZWJ
               "\xf0\x9f\x91\xa7"    # 👧 (1F467)

suite "M13: input grapheme-cluster cursor":
  test "test_input_grapheme_cursor":
    let h = newTerminalTestHarness(20, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "", width = 12, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    # Insert the family cluster as a single string (pilot.type emits one
    # keydown per codepoint; we use insertText directly to deliver it as
    # one cluster — the same path printable keys use under the hood when
    # composing a real grapheme).
    inp.insertText(family)
    h.flush()

    # The string holds 18 bytes / 5 codepoints.
    check inp.value.len == 18

    # But it is one grapheme cluster: cursor sits at index 1, not 5.
    check inp.cursorPos == 1
    # Cell offset is 2, not 5.
    check inp.cursorCellOffset == 2

    # Backspace deletes the entire cluster.
    p.press("backspace")
    check inp.value.len == 0
    check inp.cursorPos == 0
    h.dispose()

  test "left_right_navigate_by_cluster":
    let h = newTerminalTestHarness(30, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "", width = 20, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    # Compose: 'a' + family + 'b'. Three clusters total.
    inp.insertText("a")
    inp.insertText(family)
    inp.insertText("b")
    check inp.cursorPos == 3        # three clusters
    check inp.value.len == 1 + 18 + 1
    # Step left through clusters.
    p.press("left")
    check inp.cursorPos == 2
    p.press("left")
    check inp.cursorPos == 1        # past the family in one step
    p.press("left")
    check inp.cursorPos == 0
    p.press("right")
    check inp.cursorPos == 1
    h.dispose()

  test "wide_emoji_cell_offset_is_2":
    let h = newTerminalTestHarness(30, 3)
    var inp: InputWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      inp = newInput(r, value = "", width = 20, border = bsRound)
      r.appendChild(root, inp.node)
      root)
    let p = newPilot(h)
    p.focus(inp.node)
    inp.insertText(family)
    h.flush()
    # cursorCellOffset must be 2 for the single wide cluster.
    check inp.cursorCellOffset == 2
    h.dispose()
