## test_real_tier1 — M29 Tier-1 widget coverage in a real pty.
##
## Static is covered by `test_real_static.nim`. This file holds the
## remaining Tier-1 widgets: Label, Container, Button, Switch,
## Checkbox, Input.

import std/[unittest, times]

import term_assert

import ./test_helpers
import ./diagnostics

template realTest(name: string; appStem: string; body: untyped) =
  test name:
    compileApp(appStem)
    let bin = childAppPath(appStem)
    var sess {.inject.} = newTuiTest(bin, @[]).width(40).height(10).spawn()
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

suite "M29 real terminal: Tier-1":

  realTest("test_real_label_render_and_toggle", "label_app"):
    sess.waitForText("label-initial", initDuration(seconds = 5))
    sess.send("x")
    sess.waitForText("label-toggled", initDuration(seconds = 5))

  realTest("test_real_container_swap", "container_app"):
    sess.waitForText("child-A", initDuration(seconds = 5))
    sess.waitForText("child-B", initDuration(seconds = 5))
    sess.send("x")
    sess.waitForText("child-B", initDuration(seconds = 5))

  realTest("test_real_button_keyboard_activation", "button_app"):
    sess.waitForText("press-me", initDuration(seconds = 5))
    sess.send("a")
    sess.waitForText("clicked-1", initDuration(seconds = 5))

  realTest("test_real_switch_toggle", "switch_app"):
    sess.waitForText("marker:off", initDuration(seconds = 5))
    sess.send("t")
    sess.waitForText("marker:on", initDuration(seconds = 5))

  realTest("test_real_checkbox_toggle", "checkbox_app"):
    sess.waitForText("state:unchecked", initDuration(seconds = 5))
    sess.send("t")
    sess.waitForText("state:checked", initDuration(seconds = 5))

  realTest("test_real_input_typing", "input_app"):
    sess.waitForText("echo:", initDuration(seconds = 5))
    sess.send("h")
    sess.waitForText("echo:h", initDuration(seconds = 5))
    sess.send("i")
    sess.waitForText("echo:hi", initDuration(seconds = 5))
