## test_web_driver_caps_declaration — the browser client's DECLARED
## capabilities reach the app (CodeTracer-TUI-Terminal-Adaptation.md §3.5).
##
## *Claim.* xterm.js behind isonim-tui-serve cannot answer an app's start-up
## queries, so its page sends `M caps|<json>` as its first packet. The
## WebDriver's reader thread reads it off the real input pipe, and the app
## gets it from `declaredCaps` / `waitForCaps` — before its first frame when
## it waits — with every field as declared. A malformed declaration is not
## believed (`declared` false), and the packets around it are still
## delivered.
##
## Real-stack: a real OS pipe, the driver's real reader thread, the
## production packet framing. No mocks.

import std/[monotimes, posix, times, unittest]

import isonim_tui

proc writeAll(fd: cint; s: string) =
  var off = 0
  while off < s.len:
    let n = posix.write(fd, unsafeAddr s[off], s.len - off)
    doAssert n > 0
    off += int(n)

const Body = "{\"xtermJs\":\"5.3.0\",\"renderer\":\"webgl\"," &
             "\"customGlyphs\":true,\"unicodeVersion\":\"11\"," &
             "\"truecolor\":true,\"sgrMouse\":true}"

suite "WebDriver: the client's capability declaration":

  test "a declaration sent first is read before the app's first frame":
    when defined(windows):
      skip()
    else:
      var fds: array[2, cint]
      check posix.pipe(fds) == 0
      let devNull = posix.open("/dev/null", O_WRONLY)
      let wd = newWebDriver(80, 24, inputFd = fds[0], outputFd = devNull)
      check not wd.declaredCaps().declared
      wd.start()
      writeAll(fds[1], encodePacket(PacketTypeMeta, CapsMetaPrefix & Body) &
                       encodePacket(PacketTypeMeta, "resize|100|30"))
      let started = getMonoTime()
      let c = wd.waitForCaps(2000)
      checkpoint("declared after " & $(getMonoTime() - started).inMilliseconds & " ms")
      check c.declared
      check c.xtermJs == "5.3.0"
      check c.renderer == "webgl"
      check c.customGlyphs
      check c.unicodeVersion == "11"
      check c.truecolor and c.sgrMouse
      # The packet after it is delivered as before.
      var resized = false
      let deadline = getMonoTime() + initDuration(seconds = 2)
      while not resized and getMonoTime() < deadline:
        for ev in wd.readEvents():
          if ev.kind == ekResize and ev.resize.cols == 100: resized = true
      check resized
      wd.stop()
      discard posix.close(fds[1])
      discard posix.close(fds[0])
      discard posix.close(devNull)

  test "a malformed declaration is not believed":
    check not parseDeclaredCaps("{").declared
    check not parseDeclaredCaps("[]").declared
    check not parseDeclaredCaps("{\"xtermJs\":\"5.3.0\"}").declared
    check parseDeclaredCaps(Body).declared

  test "without a declaration, waiting gives up at its bound":
    when defined(windows):
      skip()
    else:
      var fds: array[2, cint]
      check posix.pipe(fds) == 0
      let devNull = posix.open("/dev/null", O_WRONLY)
      let wd = newWebDriver(80, 24, inputFd = fds[0], outputFd = devNull)
      wd.start()
      let started = getMonoTime()
      check not wd.waitForCaps(100).declared
      check (getMonoTime() - started).inMilliseconds >= 100
      wd.stop()
      discard posix.close(fds[1])
      discard posix.close(fds[0])
      discard posix.close(devNull)
