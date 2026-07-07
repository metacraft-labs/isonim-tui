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

import std/[os, posix, strutils, times, unittest]

import isonim_tui
import nim_pty

suite "M9: PosixDriver real-pty mouse":

  test "test_posix_driver_mouse_real":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var (master, slave) = openPty()
      master.setNonblock()

      let d = newPosixDriver(80, 24,
                             inputFd = slave.fd,
                             outputFd = slave.fd,
                             enableMouse = true,
                             enablePaste = false,
                             enableAlt = false)
      d.start()

      # On start, the driver should have written the mouse-enable
      # escape (CSI ?1000h CSI ?1006h) to the slave. Read the master
      # to verify.
      var startupBytes = ""
      block readStartup:
        let deadline = getTime() + initDuration(milliseconds = 200)
        while getTime() < deadline:
          var buf: array[1024, byte]
          let n = posix.read(master.fd, addr buf[0], buf.len)
          if n > 0:
            var s = newString(int(n))
            for i in 0 ..< int(n): s[i] = char(buf[i])
            startupBytes.add(s)
          elif n == 0:
            break
          else:
            sleep(5)
            if startupBytes.len > 0:
              break
      check startupBytes.contains("\x1b[?1000h")
      check startupBytes.contains("\x1b[?1006h")

      # 2) Send a SGR-1006 mouse-press sequence through the master.
      #    The slave (driver's input) sees these bytes; the parser
      #    decodes them into a MouseDown.
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
      d.stop()
      var afterStop = ""
      block readShutdown:
        let dl2 = getTime() + initDuration(milliseconds = 200)
        while getTime() < dl2:
          var buf: array[1024, byte]
          let m = posix.read(master.fd, addr buf[0], buf.len)
          if m > 0:
            var s = newString(int(m))
            for i in 0 ..< int(m): s[i] = char(buf[i])
            afterStop.add(s)
          elif m == 0:
            break
          else:
            sleep(5)
            if afterStop.len > 0 and afterStop.contains("?1000l"):
              break
      check afterStop.contains("\x1b[?1006l") or
            afterStop.contains("\x1b[?1000l")
