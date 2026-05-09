## test_web_driver_packet_roundtrip — M26 mandatory test.
##
## *Claim.* The same app, driven by the same logical event sequence
## (resize → key → key → quit), produces a byte-identical final
## ScreenBuffer when the events come from a Pilot vs from packets
## decoded by WebDriver's reader thread.
##
## *How.*
##
##   1. Build a tiny counter app twice (one harness per leg).
##   2. Leg 1: drive via `Pilot.press("a"); Pilot.press("b")`.
##   3. Leg 2: write a real packet sequence
##      (resize → key 'a' → key 'b' → quit) to a real OS pipe whose
##      read end is the WebDriver's `inputFd`. The driver's reader
##      thread decodes the packets, surfaces them on its event
##      channel; the test loop drains them and routes each into the
##      app via `fireEventWith` (mirroring what the harness's runtime
##      loop would do).
##   4. Compare the final `ScreenBuffer`s.
##
## Real-stack: no mocks. The packet bytes flow through a real OS
## pipe; the driver reads them with a real `posix.read`; the parser
## is the production module.

import std/[os, posix, times, unittest, unicode]

import isonim_tui

proc buildCounterApp(r: TerminalRenderer; counterRef: ptr int): TerminalNode =
  let root = r.createElement("div")
  r.setAttribute(root, "id", "main")
  let lbl = r.createTextNode("0")
  r.appendChild(root, lbl)
  let cap = counterRef
  r.addEventListener(root, "keydown", proc() =
    inc cap[]
    r.setTextContent(lbl, $cap[]))
  root

suite "M26: WebDriver packet round-trip":

  test "test_web_driver_packet_roundtrip":
    when defined(windows):
      skip()
    else:
      # ---- Leg 1: Pilot.press through HeadlessDriver ----
      var counterA = 0
      let hA = newTerminalTestHarness(40, 5)
      hA.mount(proc(r: TerminalRenderer): TerminalNode =
        buildCounterApp(r, addr counterA))
      let pA = newPilot(hA)
      pA.press("a")
      pA.press("b")
      let finalA = hA.screenBuffer()
      check counterA == 2
      hA.dispose()

      # ---- Leg 2: packets through WebDriver ----
      # Real pipe pair: the test writes packet bytes to the writer end,
      # the driver's reader thread reads them from the reader end.
      var pipefd: array[2, cint]
      check posix.pipe(pipefd) == 0
      let readEnd = pipefd[0]
      let writeEnd = pipefd[1]
      let devNull = posix.open("/dev/null", O_WRONLY)
      check devNull >= 0

      let wd = newWebDriver(40, 5,
                            inputFd = readEnd,
                            outputFd = devNull)
      wd.start()
      check wd.state == dsRunning

      # We use a fresh harness (which runs the compositor and a
      # HeadlessDriver mirror) for the *app side*. The WebDriver's
      # role is just to surface input events; the app is dispatched
      # against the harness's renderer/root.
      var counterB = 0
      let hB = newTerminalTestHarness(40, 5)
      hB.mount(proc(r: TerminalRenderer): TerminalNode =
        buildCounterApp(r, addr counterB))

      proc sendPacket(kind: char; payload: string) =
        let packet = encodePacket(kind, payload)
        var off = 0
        while off < packet.len:
          let p = cast[pointer](cast[uint](unsafeAddr packet[0]) + uint(off))
          let n = posix.write(writeEnd, p, packet.len - off)
          check n > 0
          off += int(n)

      # Sequence: resize → key 'a' → key 'b' → quit.
      sendPacket(PacketTypeMeta, "resize|40|5")
      sendPacket(PacketTypeInput, "key|a|97|")
      sendPacket(PacketTypeInput, "key|b|98|")
      sendPacket(PacketTypeMeta, "quit")

      # Drain events with a deadline.
      var sawQuit = false
      var receivedEvents: seq[TerminalEvent] = @[]
      let deadline = getTime() + initDuration(milliseconds = 2000)
      while getTime() < deadline and not sawQuit:
        let evs = wd.readEvents()
        for ev in evs:
          receivedEvents.add ev
          case ev.kind
          of ekResize:
            wd.resize(ev.resize.cols, ev.resize.rows)
            hB.resize(ev.resize.cols, ev.resize.rows)
          of ekKey:
            if ev.key.key == "ctrl+c":
              sawQuit = true
            else:
              fireEventWith(hB.root, "keydown", ev)
              hB.flush()
          else:
            discard
        if not sawQuit and evs.len == 0:
          sleep(10)

      check sawQuit
      check counterB == 2
      check receivedEvents.len == 4

      let finalB = hB.screenBuffer()
      hB.dispose()
      wd.stop()
      discard posix.close(writeEnd)
      discard posix.close(readEnd)
      discard posix.close(devNull)

      # ---- byte-identical final ScreenBuffer ----
      check finalB == finalA

      # Visible state: '2' at (0, 0).
      let cell00 = finalB[0, 0]
      check cell00.rune == Rune('2'.ord)
