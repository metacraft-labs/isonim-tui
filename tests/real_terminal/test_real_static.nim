## test_real_static — M29 Tier-1.
##
## Spawn `apps/static_app` under a real pty, observe the initial
## bordered Static text, send a key to cycle the label, observe the
## new label.

import std/[unittest, times]

import term_assert

import ./test_helpers
import ./diagnostics

suite "M29 real terminal: Static":

  test "test_real_static_render_and_cycle":
    compileApp("static_app")
    let bin = childAppPath("static_app")
    var sess = newTuiTest(bin, @[]).width(40).height(6).spawn()
    try:
      sess.waitForText("hello-static", initDuration(seconds = 5))
      sess.send("x")
      sess.waitForText("second-line", initDuration(seconds = 5))
      sess.send("q")
      discard sess.waitExit(initDuration(seconds = 3))
    except CatchableError as e:
      writeFailureBundle(sess, "test_real_static_render_and_cycle", e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()
