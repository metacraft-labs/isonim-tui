## test_real_special_cases — M29 special-case scenarios.
##
## Alt-screen lifecycle, SIGWINCH resize, focus-after-modal-close,
## signal handling.

import std/[unittest, os, posix, strutils, times]

import term_assert

import ./test_helpers
import ./diagnostics

suite "M29 real terminal: special cases":

  test "test_real_alt_screen_cleanup":
    compileApp("alt_screen_app")
    let bin = childAppPath("alt_screen_app")
    var sess = newTuiTest(bin, @[]).width(40).height(6).spawn()
    try:
      sess.waitForText("alt-marker", initDuration(seconds = 5))
      sess.send("q")
      let ec = sess.waitExit(initDuration(seconds = 5))
      check ec.isSome
      # The screen contents at this point should still hold the marker
      # libvterm rendered while in alt-screen. The alt-screen-leave
      # sequence is consumed by libvterm; we don't see the host
      # terminal restore from inside the harness, but we DO observe
      # that the child exited cleanly with exit code 0 — that's the
      # most reliable proof we have without an outer harness.
      check ec.get == 0
    except CatchableError as e:
      writeFailureBundle(sess, "test_real_alt_screen_cleanup", e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()

  test "test_real_sigwinch_resize":
    compileApp("resize_app")
    let bin = childAppPath("resize_app")
    var sess = newTuiTest(bin, @[]).width(80).height(24).spawn()
    try:
      sess.waitForText("size:80x24", initDuration(seconds = 5))
      # Trigger a real SIGWINCH by resizing the underlying pty.
      sess.setWindowSize(120, 40)
      sess.waitForText("size:120x40", initDuration(seconds = 5))
      sess.send("q")
      discard sess.waitExit(initDuration(seconds = 5))
    except CatchableError as e:
      writeFailureBundle(sess, "test_real_sigwinch_resize", e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()

  test "test_real_focus_after_modal_close":
    compileApp("focus_modal_app")
    let bin = childAppPath("focus_modal_app")
    var sess = newTuiTest(bin, @[]).width(60).height(12).spawn()
    try:
      sess.waitForText("input:", initDuration(seconds = 5))
      sess.send("a")
      sess.waitForText("input:a", initDuration(seconds = 5))
      sess.send("o")
      sess.waitForText("modal:open", initDuration(seconds = 5))
      sess.send("c")
      sess.waitForText("modal:closed", initDuration(seconds = 5))
      # Focus should be back on the input — typing should land there.
      sess.send("b")
      sess.waitForText("input:ab", initDuration(seconds = 5))
      sess.send("q")
      discard sess.waitExit(initDuration(seconds = 5))
    except CatchableError as e:
      writeFailureBundle(sess, "test_real_focus_after_modal_close", e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()

  test "test_real_signal_handling":
    compileApp("signal_app")
    let bin = childAppPath("signal_app")
    var sess = newTuiTest(bin, @[]).width(40).height(6).spawn()
    try:
      sess.waitForText("ready-for-signal", initDuration(seconds = 5))
      # Send SIGINT (Ctrl-C). The child's signal handler quits with
      # exit code 130. We don't compare `stty -a` because the slave
      # side of the pty's termios state isn't reliably introspectable
      # post-exit; the exit-code observation is the load-bearing
      # signal that signal handling worked.
      sess.sendSignal(SIGINT)
      let ec = sess.waitExit(initDuration(seconds = 5))
      check ec.isSome
      check ec.get == 130
    except CatchableError as e:
      writeFailureBundle(sess, "test_real_signal_handling", e.msg)
      sess.terminate()
      sess.close()
      raise
    sess.close()

  test "test_real_no_orphan_processes":
    compileApp("static_app")
    let bin = childAppPath("static_app")
    # Run 100 short sessions back-to-back. After the loop, no zombies
    # should remain — `=destroy` reaps each child via waitpid before
    # the next one starts.
    for i in 0 ..< 100:
      var sess = newTuiTest(bin, @[]).width(40).height(6).spawn()
      sess.waitForText("hello-static", initDuration(seconds = 5))
      sess.send("q")
      discard sess.waitExit(initDuration(seconds = 3))
      sess.close()
    # Reap-any-stragglers check: the kernel returns ECHILD when no
    # children remain. waitpid(-1, ..., WNOHANG) returns -1 with errno
    # = ECHILD when there's nothing to reap.
    var status: cint
    let r = waitpid(-1, status, WNOHANG)
    check r <= 0
