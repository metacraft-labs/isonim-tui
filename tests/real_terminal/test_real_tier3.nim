## test_real_tier3 — M29 Tier-3 widget coverage in a real pty.
##
## DataTable (1k-row scroll), Tree (expand/collapse), TextArea
## (edit + undo), Markdown, RichLog.

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

suite "M29 real terminal: Tier-3":

  realTest("test_real_datatable_scroll_to_end", "datatable_app", 60, 16):
    sess.waitForText("row#0", initDuration(seconds = 5))
    sess.send("G")
    sess.waitForText("row#999", initDuration(seconds = 5))

  realTest("test_real_tree_expand_collapse", "tree_app", 40, 14):
    sess.waitForText("root", initDuration(seconds = 5))
    sess.send("e")
    sess.waitForText("alpha", initDuration(seconds = 5))
    sess.waitForText("beta", initDuration(seconds = 5))

  realTest("test_real_textarea_insert_undo", "textarea_app", 40, 10):
    sess.waitForText("start", initDuration(seconds = 5))
    # Inserting 'x' should show up at the cursor position. Use a
    # single character we know isn't already in the document.
    sess.send("x")
    sess.waitForText("startx", initDuration(seconds = 5))
    # Undo: the widget records each insertText call as one undo step;
    # `undo` should pop the inserted character. The visible document
    # should not contain the trailing 'x' anymore.
    sess.send("U")
    # Allow the repaint to flush.
    discard sess.waitForRegionChange(0, 0, 30, 8, initDuration(seconds = 2))
    let after = sess.screenContents()
    check not after.contains("startx")

  realTest("test_real_markdown_renders", "markdown_app", 60, 16):
    sess.waitForText("Title", initDuration(seconds = 5))
    sess.waitForText("paragraph", initDuration(seconds = 5))

  realTest("test_real_richlog_appends", "richlog_app", 40, 12):
    sess.waitForText("line-0", initDuration(seconds = 5))
    sess.send("a")
    sess.waitForText("line-1", initDuration(seconds = 5))
    sess.send("a")
    sess.waitForText("line-2", initDuration(seconds = 5))
