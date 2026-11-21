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
##
## The master is read continuously while the driver runs, as a terminal
## emulator reads it (`PtyMasterDrain`): on macOS the driver's `stop()`
## cannot restore termios until its output has been read, and a test that
## read the master only after `stop()` hung there forever. A
## `PhaseWatchdog` fails the test, naming the phase, if any phase blocks.
## See `pty_test_support.nim` for the kernel behaviour behind both.

import std/[posix, strutils, termios, times, unittest]

import isonim_tui
import nim_pty

import ./pty_test_support

suite "M9: PosixDriver real-pty round trip":

  test "test_posix_driver_real_pty":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var wd = startPhaseWatchdog("test_posix_driver_real_pty",
                                  initDuration(seconds = 20), "openPty")
      defer: stopPhaseWatchdog(wd)

      # 1) Allocate a real pty pair, and read its master the way a
      #    terminal emulator does for as long as the driver runs.
      var (master, slave) = openPty()
      # The reader-thread side wants the slave readable without
      # blocking the test forever; mark non-blocking.
      slave.setNonblock()
      var drain = startMasterDrain(master.fd)
      defer: stopMasterDrain(drain)

      # 2) Capture the slave's pre-start termios so we can verify the
      #    "restored to cooked mode" claim later.
      var savedTermios: Termios
      check tcGetAttr(slave.fd, addr savedTermios) == 0
      let savedLflag = savedTermios.c_lflag

      # 3) Build a driver running on the slave FD.
      wd.phase("newPosixDriver + start")
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
      wd.phase("writeRaw + write + flushPending")
      let strip = newStrip(@[
        newCell('h'), newCell('e'), newCell('l'), newCell('l'),
        newCell('o')])
      d.writeRaw(cursorTo(0, 0))
      d.write(strip)
      d.flushPending()

      # The mirror should hold the cursor-to + payload bytes.
      check d.bytesEmitted.contains("hello")

      # 5) Stop. termios must be restored to its pre-start state.
      wd.phase("stop")
      d.stop()
      check d.state == dsStopped

      var restored: Termios
      check tcGetAttr(slave.fd, addr restored) == 0
      check restored.c_lflag == savedLflag

      # 6) The master must have received alt-screen-enter, the payload,
      #    and alt-screen-leave. `stop()` returned, so on macOS all of it
      #    has already been read; Linux may still be delivering it.
      wd.phase("read the master")
      check drain.waitForOutput("\x1b[?1049l", initDuration(seconds = 5))
      let allOutput = drain.output
      checkpoint "master output: " & allOutput.repr
      check allOutput.contains("\x1b[?1049h")  # enter alt-screen
      check allOutput.contains("\x1b[?1049l")  # leave alt-screen
      check allOutput.contains("hello")
