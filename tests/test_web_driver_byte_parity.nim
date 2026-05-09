## test_web_driver_byte_parity — M26 mandatory test.
##
## *Claim.* For the same compositor write sequence, the concatenation
## of WebDriver's `D` packet payloads equals the byte stream
## PosixDriver writes to stdout (modulo trailing flush). This is the
## byte-identical-replay claim from the M26 spec.
##
## *How.* Drive both drivers through the same scripted sequence of
## `writeRaw` / `writeAt` / `flushPending` calls and compare the
## bytes each driver records on its `bytesEmitted` mirror. Both
## drivers compute that mirror from the *exact same encoding path*
## (SGR transitions + UTF-8 cell payloads) — so any divergence would
## be a bug in one of them, not in the test.
##
## We deliberately avoid `start()` on PosixDriver here: that path
## claims the host terminal (raw mode, alt-screen, atexit hooks) and
## isn't needed to assert byte parity over the buffered-write path.
## A separate test (`test_posix_driver_real_pty`) covers the start /
## stop side already.
##
## Real-stack: no mocks. Both drivers are the real production
## modules; the strips and raw byte runs are the same value-typed
## constructions the compositor emits.

import std/[posix, strutils, unicode, unittest]

import isonim_tui

suite "M26: WebDriver / PosixDriver byte parity":

  test "test_web_driver_byte_parity":
    when defined(windows):
      skip()
    else:
      let cols = 40
      let rows = 5

      # Build a mixed-width strip: ASCII + a stylised run + a CJK rune.
      proc makeRow(): Strip =
        var cells: seq[Cell] = @[]
        for ch in "hello":
          cells.add newCell(ch)
        # SGR transition: bold + indexed-color cells.
        let styled = newCell('!', fg = ansiColor(acRed),
                             attrs = {attrBold})
        cells.add styled
        # ASCII space then a wide rune (CJK U+4e2d "中" — width 2).
        cells.add newCell(' ')
        let wide = newCell(Rune(0x4e2d))
        cells.add wide
        # Trailing pad cells to bring the strip up to cols.
        while cells.len < cols:
          cells.add spaceCell()
        newStrip(cells)

      let strip = makeRow()

      # ---- WebDriver ----
      # The writeStringAll inside flushPending() needs a writable FD
      # even though we're not consuming the bytes; route to /dev/null.
      let devNull = posix.open("/dev/null", O_WRONLY)
      check devNull >= 0
      # The reader side is unused in this test (we don't call start);
      # passing -1 keeps it a no-op.
      let wd = newWebDriver(cols, rows,
                            inputFd = -1.cint,
                            outputFd = devNull)
      # Mimic the compositor's first paint: one cursor-to per row, one
      # writeAt per row, then a single flushPending.
      wd.writeRaw(cursorTo(0, 0))
      for r in 0 ..< rows:
        wd.writeAt(r, strip)
      wd.flushPending()
      # Sanity: flushPending wrote exactly one D packet header + payload
      # to packetsEmitted.
      check wd.packetsEmitted.len == 5 + wd.bytesEmitted.len
      check wd.packetsEmitted[0] == 'D'

      # ---- PosixDriver ----
      # Don't call start() — it claims the host terminal. The buffered
      # write path doesn't need it. flushPending will write to the FD
      # we hand it; route to /dev/null too.
      let devNull2 = posix.open("/dev/null", O_WRONLY)
      check devNull2 >= 0
      let pd = newPosixDriver(cols, rows,
                              inputFd = -1.cint,
                              outputFd = devNull2,
                              enableMouse = false,
                              enablePaste = false,
                              enableAlt = false)
      pd.writeRaw(cursorTo(0, 0))
      for r in 0 ..< rows:
        pd.writeAt(r, strip)
      pd.flushPending()

      # The byte-identical claim:
      check wd.bytesEmitted == pd.bytesEmitted

      # And: re-extract WebDriver's bytes from the packet stream.
      # `D` packet header is 5 bytes; payload follows.
      var extracted = ""
      var off = 0
      while off + 5 <= wd.packetsEmitted.len:
        let kind = wd.packetsEmitted[off]
        let n = (uint32(byte(wd.packetsEmitted[off + 1])) shl 24) or
                (uint32(byte(wd.packetsEmitted[off + 2])) shl 16) or
                (uint32(byte(wd.packetsEmitted[off + 3])) shl 8) or
                uint32(byte(wd.packetsEmitted[off + 4]))
        check kind == 'D'
        let payload = wd.packetsEmitted[(off + 5) ..< (off + 5 + int(n))]
        extracted.add(payload)
        off += 5 + int(n)
      check extracted == pd.bytesEmitted

      discard posix.close(devNull)
      discard posix.close(devNull2)

  test "test_web_driver_packet_framing_round_trip":
    ## Round-trip the framing helpers — what `encodePacket` builds,
    ## `feedBytes` -> `pop` decodes back to the same `(kind, payload)`.
    when defined(windows):
      skip()
    else:
      var p = initPacketParser()
      let pkts = @[
        ('D', "hello"),
        ('M', "resize|40|5"),
        ('P', "key|enter|0|"),
        ('D', ""),
        ('P', "key|a|97|"),
      ]
      var combined = ""
      for (k, v) in pkts:
        combined.add encodePacket(k, v)
      # Feed in 7-byte chunks to exercise partial-packet carry-over.
      var i = 0
      while i < combined.len:
        let j = min(i + 7, combined.len)
        var seg = newSeq[byte](j - i)
        for k in 0 ..< (j - i): seg[k] = byte(combined[i + k])
        p.feedBytes(seg)
        i = j
      check p.pendingPackets() == pkts.len
      var decoded: seq[(char, string)] = @[]
      while p.pendingPackets() > 0:
        let (ok, kind, payload) = p.pop()
        check ok
        decoded.add (kind, payload)
      check decoded == pkts
