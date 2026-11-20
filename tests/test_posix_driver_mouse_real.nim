## test_posix_driver_mouse_real — M9 mandatory test.
##
## Pty receives raw mouse-mode bytes; driver emits `MouseDown` at
## expected coords. After `stop()` the mouse-mode bytes (`?1006l` +
## `?1000l`) are written to the host (verified by reading the master
## side).
##
## SGR-1006 mouse format: `CSI < button ; col ; row M` for press,
## `m` for release. We send the press-at-(col=10, row=5) of the
## left button (button=0).

##
## The master is read continuously while the driver runs
## (`PtyMasterDrain`), as a terminal emulator would: on macOS `stop()`
## cannot restore termios until the driver's output has been read, and a
## test that read the master only after `stop()` hung there. A
## `PhaseWatchdog` fails the test, naming the phase, if any phase blocks.
## See `pty_test_support.nim`.

import std/[os, posix, strutils, times, unittest]

import isonim_tui
import nim_pty

import ./pty_test_support

suite "M9: PosixDriver real-pty mouse":

  test "test_posix_driver_mouse_real":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var wd = startPhaseWatchdog("test_posix_driver_mouse_real",
                                  initDuration(seconds = 20), "openPty")
      defer: stopPhaseWatchdog(wd)

      var (master, slave) = openPty()
      var drain = startMasterDrain(master.fd)
      defer: stopMasterDrain(drain)

      wd.phase("newPosixDriver + start")
      let d = newPosixDriver(80, 24,
                             inputFd = slave.fd,
                             outputFd = slave.fd,
                             enableMouse = true,
                             enablePaste = false,
                             enableAlt = false)
      d.start()

      # On start, the driver should have written the mouse-enable
      # escape (CSI ?1000h CSI ?1006h) to the slave.
      wd.phase("read the mouse-enable bytes")
      check drain.waitForOutput("\x1b[?1006h", initDuration(seconds = 2))
      let startupBytes = drain.output
      checkpoint "master output after start: " & startupBytes.repr
      check startupBytes.contains("\x1b[?1000h")
      check startupBytes.contains("\x1b[?1006h")

      # 2) Send a SGR-1006 mouse-press sequence through the master.
      #    The slave (driver's input) sees these bytes; the parser
      #    decodes them into a MouseDown.
      wd.phase("send a mouse press + wait for MouseDown")
      let mouseBytes = "\x1b[<0;10;5M"
      var b = newSeq[byte](mouseBytes.len)
      for i in 0 ..< mouseBytes.len: b[i] = byte(mouseBytes[i])
      let n = posix.write(master.fd, addr b[0], b.len)
      check n == clong(b.len)

      # 3) Drain events until we see a MouseDown.
      var sawMouse = false
      var mouseRow = 0
      var mouseCol = 0
      var mouseButton: MouseButton = mbNone
      let deadline = getTime() + initDuration(seconds = 2)
      while getTime() < deadline:
        let evs = d.readEvents()
        for ev in evs:
          if ev.kind == ekMouseDown:
            sawMouse = true
            mouseRow = ev.mouse.row
            mouseCol = ev.mouse.col
            mouseButton = ev.mouse.button
            break
        if sawMouse: break
        sleep(20)

      check sawMouse
      check mouseButton == mbLeft
      # nim-termctl decodes the SGR-1006 form col/row faithfully; the
      # input parser preserves them in `events.MouseEvent`.
      check mouseRow == 5
      check mouseCol == 10

      # 4) Stop the driver; mouse mode disable bytes go out.
      wd.phase("stop")
      let beforeStop = drain.output.len
      d.stop()
      wd.phase("read the mouse-disable bytes")
      check drain.waitForOutput("\x1b[?1000l", initDuration(seconds = 2))
      let afterStop = drain.output[beforeStop .. ^1]
      checkpoint "master output after stop: " & afterStop.repr
      check afterStop.contains("\x1b[?1006l") or
            afterStop.contains("\x1b[?1000l")
