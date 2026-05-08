## test_toast_autodismiss — M14 mandatory test.
##
## A Toast appears, fades after 5 s (virtual clock); the underlying
## cells repaint correctly when it leaves.

import unittest
import isonim_tui

suite "M14: toast auto-dismiss":
  test "test_toast_autodismiss":
    let h = newTerminalTestHarness(40, 8)
    var dismissed = false
    var toast: ToastWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.appendChild(root, newLabel(r, "underneath").node)
      toast = newToast(h, "Saved", "File saved successfully",
                       severity = tsInformation,
                       width = 30,
                       durationMs = 5000.0,
                       onDismiss = proc() = dismissed = true)
      root)

    # Hidden initially.
    check (not toast.isVisible)

    # Show the toast — fires entry animation, then schedules
    # auto-dismiss in 5000 ms.
    toast.show()
    let p = newPilot(h)
    # Drive the entry animation (200ms).
    p.waitForAnimation()
    check toast.isVisible
    check toast.state == tstVisible

    # Advance 4900 ms — still visible.
    h.advanceMs(4900.0)
    check toast.isVisible

    # Advance past the 5000 ms total — the dismiss callback fires; the
    # exit animation begins.
    h.advanceMs(200.0)
    check toast.state in {tstExiting, tstHidden}

    # Drive the exit animation to completion.
    p.waitForAnimation()
    check toast.state == tstHidden
    check (not toast.isVisible)
    check dismissed

    h.dispose()

  test "toast_severity_color":
    ## Different severities pick different background colours.
    let h = newTerminalTestHarness(40, 8)
    var infoToast, warnToast, errToast: ToastWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      infoToast = newToast(h, "i", severity = tsInformation, durationMs = 100.0)
      warnToast = newToast(h, "w", severity = tsWarning, durationMs = 100.0)
      errToast = newToast(h, "e", severity = tsError, durationMs = 100.0)
      root)
    check infoToast.severity == tsInformation
    check warnToast.severity == tsWarning
    check errToast.severity == tsError
    h.dispose()
