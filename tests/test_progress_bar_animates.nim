## test_progress_bar_animates — M21 mandatory test.
##
## ProgressBar advances 0 → 100% over 5,000 ms with `linear` easing.
## We snapshot the underlying `progress` reactive at 25 / 50 / 75 /
## 100 % to verify the M7 animator is actually driving the widget.
## All work goes through the real animator + real harness; the only
## "fake" is the virtual TestClock baked into the harness.

import unittest
import isonim_tui

const Tolerance = 0.5  # half a percentage-point of slack at each
                       # checkpoint, since the animator ticks at 60 Hz
                       # and our snapshot points fall mid-frame.

suite "M21: ProgressBar animates linearly via M7":

  test "test_progress_bar_animates":
    let h = newTerminalTestHarness(50, 4)
    var pb: ProgressBarWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      pb = newProgressBar(h, total = 100.0, progress = 0.0,
                          width = 40, showPercent = true)
      r.appendChild(root, pb.node)
      root)

    check abs(pb.progress) < 1e-9
    check pb.percentageInt == 0

    # Kick off the animation: 0 → 100 over 5,000 ms with linear easing.
    pb.animateTo(target = 100.0, durationMs = 5000.0,
                 easingFn = easeLinear)

    # Sample at 25 / 50 / 75 / 100 % (1.25s / 2.5s / 3.75s / 5s).
    h.advanceMs(1250.0)
    check abs(pb.progress - 25.0) <= Tolerance

    h.advanceMs(1250.0)
    check abs(pb.progress - 50.0) <= Tolerance

    h.advanceMs(1250.0)
    check abs(pb.progress - 75.0) <= Tolerance

    h.advanceMs(1250.0)
    # Final tick may overshoot the end; the animator clamps to the
    # target.
    check abs(pb.progress - 100.0) <= Tolerance
    check pb.percentageInt == 100

    h.advanceMs(20.0)
    check h.animator.activeCount == 0
    check abs(pb.progress - 100.0) <= 1e-9

    h.dispose()

  test "progress_bar_clamps":
    ## Out-of-range values clamp before the percentage label is built.
    let h = newTerminalTestHarness(20, 2)
    var pb: ProgressBarWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      pb = newProgressBar(h, total = 100.0, progress = 200.0, width = 16)
      let root = r.createElement("div")
      r.appendChild(root, pb.node)
      root)
    check pb.percentageInt == 100
    pb.setProgress(-50.0)
    check pb.percentageInt == 0
    h.dispose()

  test "progress_bar_indeterminate":
    ## When `total <= 0` the widget enters the indeterminate marquee
    ## mode. The animator can drive the offset signal independently of
    ## the determinate progress signal.
    let h = newTerminalTestHarness(40, 2)
    var pb: ProgressBarWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      pb = newProgressBar(h, total = -1.0, progress = 0.0, width = 30)
      let root = r.createElement("div")
      r.appendChild(root, pb.node)
      root)
    check pb.isIndeterminate
    pb.startIndeterminateAnimation(cycleMs = 600.0)
    check h.animator.activeCount >= 1
    h.advanceMs(150.0)
    let mid = pb.indeterminateOffset
    check mid > 0.0
    check mid < 1.0
    pb.cancelIndeterminate()
    check (not pb.h.animator.isAnimating(pb.node.id, "indeterminate"))
    h.dispose()

  test "progress_bar_advance":
    ## `advance` increments by a delta — useful for streaming updates.
    let h = newTerminalTestHarness(20, 2)
    var pb: ProgressBarWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      pb = newProgressBar(h, total = 10.0, progress = 0.0, width = 16)
      let root = r.createElement("div")
      r.appendChild(root, pb.node)
      root)
    for _ in 0 ..< 5: pb.advance(1.0)
    check abs(pb.progress - 5.0) < 1e-9
    check pb.percentageInt == 50
    h.dispose()
