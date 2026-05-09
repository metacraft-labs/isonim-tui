## test_real_cross_emulator — M29 cross-terminal-emulator suite.
##
## Status: deferred. The spec calls for `test_real_xterm_compat` /
## `test_real_kitty_compat` / `test_real_alacritty_compat` — same
## test app run under three terminal emulators. Headless CI runners
## don't have an X11 / Wayland display, so spawning real xterm /
## kitty / alacritty would require a virtual framebuffer (`Xvfb`),
## a windowing-server stack, and per-emulator integration glue.
##
## TermAssert already exercises a `libvterm`-driven pty path, which
## is the same parser real emulators ship; that's the closest
## cross-emulator approximation available without GUI infrastructure.
## Per the spec's "(where available in CI)" qualifier, this entire
## suite is deferred to a follow-up milestone that adds an Xvfb-based
## CI lane.
##
## We keep the file in the suite as a registered placeholder so the
## test runner records the deferral explicitly. The single test
## body emits a skip and exits clean.

import std/unittest

suite "M29 cross-emulator (deferred)":

  test "test_real_xterm_compat":
    # Deferred: requires Xvfb + xterm in CI. Tracked under the M29
    # cross-emulator deliverable.
    skip()

  test "test_real_kitty_compat":
    skip()

  test "test_real_alacritty_compat":
    skip()
