## test_posix_driver_resize_real — M9 mandatory test.
##
## Real pty resized via `ioctl(TIOCSWINSZ)` (which `nim_pty.setWindowSize`
## wraps). SIGWINCH fires; the driver translates the self-pipe byte
## into a `ResizeEvent` (via `pollWinchPipe`, called from `readEvents`).
## We assert the event arrives and reflects the new dimensions.
##
## *Why we manually `kill(getpid(), SIGWINCH)`*: when the slave end of
## a pty isn't the controlling terminal of the test process's session,
## the kernel won't synthesise SIGWINCH on `TIOCSWINSZ`. We do the
## ioctl (so the kernel's window-size record really updates and a
## subsequent `ioctl(TIOCGWINSZ)` reports the new dimensions) and then
## simulate the signal manually — exactly what the kernel would have
## done if the slave were the controlling terminal. The driver queries
## `terminalSize(outputFd)` when it observes the winch byte, so the
## reported (cols, rows) reflect what `setWindowSize` wrote.
##
## Test runs on Linux + macOS via the matrix. nim-pty's POSIX backend
## uses `openpty(3)` which is identical on both.

import std/[os, posix, times, unittest]

import isonim_tui
import nim_pty

# SIGWINCH constant (std/posix doesn't declare it on all platforms).
var
  TestSIGWINCH {.importc: "SIGWINCH", header: "<signal.h>".}: cint

suite "M9: PosixDriver resize via real SIGWINCH":

  test "test_posix_driver_resize_real":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      # 1) Allocate a real pty + a driver bound to its slave FD.
      var (master, slave) = openPty()
      master.setNonblock()
      master.setWindowSize(80, 24)

      let d = newPosixDriver(80, 24,
                             inputFd = slave.fd,
                             outputFd = slave.fd,
                             enableMouse = false,
                             enablePaste = false,
                             enableAlt = false)
      d.start()

      # 2) Resize via the real ioctl(TIOCSWINSZ) and synthesise the
      #    SIGWINCH the kernel would have sent if the slave were our
      #    controlling tty. Setting window size on the master updates
      #    the kernel's winsize record on the slave; our driver then
      #    queries `terminalSize(slave.fd)` from `pollWinchPipe`.
      master.setWindowSize(132, 50)
      discard kill(getpid(), TestSIGWINCH)

      # 3) Wait up to 2 seconds for the driver to surface a
      #    ResizeEvent. `readEvents` checks the winch self-pipe each
      #    time it's called.
      var sawResize = false
      var seenCols = 0
      var seenRows = 0
      let deadline = getTime() + initDuration(seconds = 2)
      while getTime() < deadline:
        let evs = d.readEvents()
        for ev in evs:
          if ev.kind == ekResize:
            sawResize = true
            seenCols = ev.resize.cols
            seenRows = ev.resize.rows
            break
        if sawResize: break
        sleep(20)

      d.stop()

      check sawResize
      check seenCols == 132
      check seenRows == 50
