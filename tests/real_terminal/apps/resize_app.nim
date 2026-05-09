## resize_app — listens for SIGWINCH; on each delivery, queries the
## current pty size and rebuilds the harness at the new dimensions,
## printing a "size:CxR" marker so a test can wait for the change.
##
## We don't use `app_runtime.runEventLoop` because we need a select()
## that wakes on SIGWINCH (not just stdin input). The event loop here
## polls every 100 ms and rebuilds when the resized flag is set.

import std/[posix, termios, monotimes, times]
import isonim_tui

var SIGWINCH {.importc, header: "<signal.h>".}: cint

var resized {.global.}: bool = false

proc onWinch(sig: cint) {.noconv.} =
  resized = true

proc emit(s: string) =
  if s.len == 0: return
  discard write(1.cint, unsafeAddr s[0], s.len)

proc paint(h: TerminalTestHarness) =
  h.flush()
  let raw = encodeAnsi(h.driver.buffer)
  var s = "\x1b[2J\x1b[H"
  var row = 1
  var line = ""
  for ch in raw:
    if ch == '\n':
      s.add "\x1b[" & $row & ";1H" & line
      line = ""
      inc row
    else:
      line.add ch
  if line.len > 0:
    s.add "\x1b[" & $row & ";1H" & line
  emit(s)

proc currentSize(): (int, int) =
  var ws: IOctl_WinSize
  let r = ioctl(1.cint, TIOCGWINSZ, addr ws)
  if r == 0: (int(ws.ws_col), int(ws.ws_row))
  else: (80, 24)

when isMainModule:
  signal(SIGWINCH, onWinch)
  var (cols, rows) = currentSize()
  var h = newTerminalTestHarness(cols, rows)
  proc build(curCols, curRows: int): TerminalTestHarness =
    let nh = newTerminalTestHarness(curCols, curRows)
    nh.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newStatic(r, "size:" & $curCols & "x" & $curRows,
                        width = 30, height = 1)
      r.appendChild(root, s.node)
      root)
    nh

  h.dispose()
  h = build(cols, rows)
  paint(h)

  let deadline = getMonoTime() + initDuration(seconds = 30)
  while getMonoTime() < deadline:
    var rs: TFdSet
    FD_ZERO(rs)
    FD_SET(0.cint, rs)
    var tv: Timeval
    tv.tv_sec = posix.Time(0)
    tv.tv_usec = clong(100_000)
    let n = posix.select(1, addr rs, nil, nil, addr tv)
    if resized:
      resized = false
      let (c, r) = currentSize()
      h.dispose()
      h = build(c, r)
      paint(h)
    if n > 0 and FD_ISSET(0.cint, rs) != 0:
      var buf: array[16, byte]
      let got = posix.read(0.cint, addr buf[0], buf.len)
      if got <= 0: break
      var sawQuit = false
      for i in 0 ..< int(got):
        if buf[i] == byte('q'): sawQuit = true
      if sawQuit: break
  h.dispose()
