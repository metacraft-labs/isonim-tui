## test_listview_keyboard_navigation — M14 mandatory test.
##
## A ListView with 8 items in a 3-row viewport. Arrow-down advances
## the highlight; PgDn jumps a page; Home / End jump to extremes. The
## test exercises the real keydown handler installed by `newListView`,
## not a synthetic one — the focus manager hands the key off to the
## focused node, the widget's listener mutates state, and a flush
## paints.

import unittest
import isonim_tui

suite "M14: listview keyboard navigation":
  test "test_listview_keyboard_navigation":
    let h = newTerminalTestHarness(40, 6)
    var lv: ListViewWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      lv = newListView(r,
        items = [
          ListItem(id: "a", label: "Apple"),
          ListItem(id: "b", label: "Banana"),
          ListItem(id: "c", label: "Cherry"),
          ListItem(id: "d", label: "Date"),
          ListItem(id: "e", label: "Elderberry"),
          ListItem(id: "f", label: "Fig"),
          ListItem(id: "g", label: "Grape"),
          ListItem(id: "h", label: "Honeydew"),
        ],
        width = 30, viewportHeight = 3)
      r.appendChild(root, lv.node)
      root)

    let p = newPilot(h)
    p.focus(lv.node)
    check lv.highlightedIndex == 0

    # Arrow-down advances by one row.
    p.press("down")
    check lv.highlightedIndex == 1
    p.press("down")
    check lv.highlightedIndex == 2

    # PgDn jumps a page (= viewportHeight = 3).
    p.press("pagedown")
    check lv.highlightedIndex == 5

    # End → last.
    p.press("end")
    check lv.highlightedIndex == 7

    # Home → first.
    p.press("home")
    check lv.highlightedIndex == 0

    # Up at first stays.
    p.press("up")
    check lv.highlightedIndex == 0

    # PgUp at first stays.
    p.press("pageup")
    check lv.highlightedIndex == 0

    h.dispose()

  test "listview_disabled_items_skipped":
    let h = newTerminalTestHarness(40, 6)
    var lv: ListViewWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      lv = newListView(r,
        items = [
          ListItem(id: "a", label: "Apple"),
          ListItem(id: "b", label: "Banana", disabled: true),
          ListItem(id: "c", label: "Cherry"),
        ],
        width = 30, viewportHeight = 3)
      r.appendChild(root, lv.node)
      root)
    let p = newPilot(h)
    p.focus(lv.node)
    check lv.highlightedIndex == 0
    p.press("down")
    # Skips disabled Banana, lands on Cherry.
    check lv.highlightedIndex == 2
    h.dispose()

  test "listview_activate_fires_callback":
    let h = newTerminalTestHarness(40, 6)
    var lv: ListViewWidget
    var activatedIdx = -1
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      lv = newListView(r,
        items = [
          ListItem(id: "a", label: "Apple"),
          ListItem(id: "b", label: "Banana"),
        ],
        width = 30, viewportHeight = 3,
        onActivate = proc(idx: int) =
          activatedIdx = idx)
      r.appendChild(root, lv.node)
      root)
    let p = newPilot(h)
    p.focus(lv.node)
    p.press("down")
    p.press("enter")
    check activatedIdx == 1
    h.dispose()
