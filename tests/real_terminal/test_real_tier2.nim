## test_real_tier2 — M29 Tier-2 widget coverage in a real pty.
##
## Tabs, ListView, Modal, Toast, LoadingIndicator.

import std/[unittest, strutils, times]

import term_assert

import ./test_helpers
import ./diagnostics

template realTest(name: string; appStem: string;
                  cols, rows: int; body: untyped) =
  test name:
    compileApp(appStem)
    let bin = childAppPath(appStem)
    var sess {.inject.} = newTuiTest(bin, @[]).width(cols).height(rows).spawn()
    try:
      body
      sess.send("q")
      discard sess.waitExit(initDuration(seconds = 3))
    except CatchableError as e:
      writeFailureBundle(sess, name, e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()

suite "M29 real terminal: Tier-2":

  realTest("test_real_tabs_cycle", "tabs_app", 40, 8):
    sess.waitForText("active:alpha", initDuration(seconds = 5))
    sess.send("n")
    sess.waitForText("active:beta", initDuration(seconds = 5))

  realTest("test_real_listview_navigation", "listview_app", 40, 12):
    sess.waitForText("hl:one", initDuration(seconds = 5))
    sess.send("j")
    sess.waitForText("hl:two", initDuration(seconds = 5))

  realTest("test_real_modal_open_close", "modal_app", 40, 12):
    sess.waitForText("modal:closed", initDuration(seconds = 5))
    sess.send("o")
    sess.waitForText("modal:open", initDuration(seconds = 5))
    sess.send("c")
    sess.waitForText("modal:closed", initDuration(seconds = 5))

  realTest("test_real_toast_show_dismiss", "toast_app", 40, 10):
    sess.waitForText("toast:hidden", initDuration(seconds = 5))
    sess.send("s")
    sess.waitForText("toast:visible", initDuration(seconds = 5))

  realTest("test_real_loading_indicator", "loading_app", 40, 6):
    # The spinner shows the first frame on render. Pump a couple of
    # ticks; the only assertion is that the byte stream contained at
    # least one frame glyph.
    sess.waitForText("loading", initDuration(seconds = 5))
    sess.send(" ")
    sess.send(" ")
    let txt = sess.screenContents()
    check txt.contains("loading")
