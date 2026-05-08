## test_posix_driver_real_pty — M9 mandatory test.
##
## Open a real pty (via nim-pty's `openPty`), run `PosixDriver` against
## the slave FD as both input and output, render an app (a single
## strip), and verify:
##
##   * Termios on the slave was switched to raw mode while the driver
##     was running.
##   * After `stop()`, termios returns to its pre-start state (cooked).
##   * The driver emitted the alt-screen-enter sequence on `start` and
##     the alt-screen-leave sequence on `stop`. Read the bytes back
##     from the master to verify.
##   * `state()` transitions stopped → running → stopped.
##
## Real-stack: no mocks. `nim_pty.openPty` allocates a real
## /dev/pts/<n> pair via `openpty(3)`; `PosixDriver` calls real
## `tcgetattr`/`tcsetattr` on the slave FD; the alt-screen escape is
## a real byte sequence written through `write(2)`.

import std/[os, posix, strutils, termios, times, unittest]

import isonim_tui
import nim_pty

suite "M9: PosixDriver real-pty round trip":

  test "test_posix_driver_real_pty":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      # 1) Allocate a real pty pair.
      var (master, slave) = openPty()
      # The reader-thread side wants the slave readable without
      # blocking the test forever; mark non-blocking.
      slave.setNonblock()
      master.setNonblock()

      # 2) Capture the slave's pre-start termios so we can verify the
      #    "restored to cooked mode" claim later.
      var savedTermios: Termios
      check tcGetAttr(slave.fd, addr savedTermios) == 0
      let savedLflag = savedTermios.c_lflag

      # 3) Build a driver running on the slave FD.
      let d = newPosixDriver(80, 24,
                             inputFd = slave.fd,
                             outputFd = slave.fd,
                             enableMouse = false,
                             enablePaste = false,
                             enableAlt = true)
      check d.state == dsStopped
      d.start()
      check d.state == dsRunning

      # While the driver is running, the slave's termios must be raw —
      # in particular ICANON and ECHO (both in c_lflag) are cleared.
      var liveTermios: Termios
      check tcGetAttr(slave.fd, addr liveTermios) == 0
      check (liveTermios.c_lflag and Cflag(ICANON)) == Cflag(0)
      check (liveTermios.c_lflag and Cflag(ECHO)) == Cflag(0)

      # 4) Simulate a render: write a strip to the driver and flush.
      let strip = newStrip(@[
        newCell('h'), newCell('e'), newCell('l'), newCell('l'),
        newCell('o')])
      d.writeRaw(cursorTo(0, 0))
      d.write(strip)
      d.flushPending()

      # The mirror should hold the cursor-to + payload bytes.
      check d.bytesEmitted.contains("hello")

      # 5) Stop. termios must be restored to its pre-start state.
      d.stop()
      check d.state == dsStopped

      var restored: Termios
      check tcGetAttr(slave.fd, addr restored) == 0
      check restored.c_lflag == savedLflag

      # 6) Read the master side to confirm the driver actually wrote
      #    alt-screen-enter, the payload, and alt-screen-leave bytes.
      var allOutput = ""
      let deadline = getTime() + initDuration(milliseconds = 200)
      while getTime() < deadline:
        var buf: array[1024, byte]
        let n = posix.read(master.fd, addr buf[0], buf.len)
        if n > 0:
          var s = newString(int(n))
          for i in 0 ..< int(n): s[i] = char(buf[i])
          allOutput.add(s)
        elif n == 0:
          break
        else:
          # EAGAIN — sleep briefly.
          sleep(5)
      # The exact bytes include the entry/leave sequences plus the
      # "hello" payload.
      check allOutput.contains("\x1b[?1049h")  # enter alt-screen
      check allOutput.contains("\x1b[?1049l")  # leave alt-screen
      check allOutput.contains("hello")
