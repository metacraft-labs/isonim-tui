## test_modal_animation_frames — M14 mandatory test.
##
## Open a modal that animates entry over 200 ms with `easeOutCubic`.
## Pin animation progress at t=0 / t=100 / t=200 ms by stepping the
## virtual clock. The progress field is the animator's current eased
## value; we assert monotonic growth and final t=full state.

import unittest
import isonim_tui

suite "M14: modal animation frames":
  test "test_modal_animation_frames":
    let h = newTerminalTestHarness(50, 12)
    var modal: ModalWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      modal = newModal(h, "Animated",
                       width = 20, height = 5,
                       animDurationMs = 200.0)
      root)

    # t=0: closed.
    check (not modal.isOpen)
    check modal.animProgress == 0.0

    modal.open()
    # Right after open() the animator has just started; progress is
    # still ~0 until the first frame fires.
    check modal.state == msOpening

    # Step ~100ms (advance virtual clock) — half-way through animation.
    h.advanceMs(100.0)
    let midProgress = modal.animProgress
    check midProgress > 0.0
    check midProgress < 1.0

    # Step the rest.
    h.advanceMs(120.0)
    let p = newPilot(h)
    p.waitForAnimation()
    check modal.animProgress == 1.0
    check modal.state == msOpen

    # Closing animation similarly.
    modal.close()
    check modal.state == msClosing
    h.advanceMs(100.0)
    let closingMid = modal.animProgress
    check closingMid < 1.0
    check closingMid > 0.0

    h.advanceMs(150.0)
    p.waitForAnimation()
    check modal.state == msClosed
    h.dispose()

  test "modal_progress_monotonic_open":
    ## Sample progress at multiple frames — must be non-decreasing
    ## while open animation runs.
    let h = newTerminalTestHarness(50, 12)
    var modal: ModalWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      modal = newModal(h, "Mono", width = 20, height = 5,
                       animDurationMs = 250.0)
      root)
    modal.open()
    var lastP = 0.0
    let frameMs = 1000.0 / 60.0
    var elapsed = 0.0
    while elapsed < 260.0:
      h.advanceMs(frameMs)
      elapsed += frameMs
      check modal.animProgress >= lastP - 1e-9
      lastP = modal.animProgress
    check modal.animProgress == 1.0
    h.dispose()
