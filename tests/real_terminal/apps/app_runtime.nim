## app_runtime.nim — shared runtime for M29 real-terminal test apps.
##
## Each per-widget test app builds a `TerminalTestHarness`, mounts a
## widget tree, and uses this runtime to:
##   * paint the harness's ScreenBuffer to stdout as ANSI bytes
##     (so the spawned pty receives a real byte stream);
##   * drive a non-blocking stdin read loop that calls a user-supplied
##     key handler;
##   * exit cleanly on EOT (Ctrl+D), 'q', or `requestQuit()`.
##
## The runtime intentionally avoids `PosixDriver` so each app stays
## under 50 LOC of widget-specific code. The bytes that flow through
## the pty are produced by the real `encodeAnsi` snapshot encoder,
## which uses the real cells / compositor / SGR layer — i.e. exactly
## the same byte path a production driver would emit, modulo the lack
## of an alt-screen wrap. Tests that need alt-screen specifically
## (e.g. `test_real_alt_screen_cleanup`) emit the sequences directly.

import std/[os, posix, times, monotimes]

import isonim_tui

type
  AppRuntime* = ref object
    h*: TerminalTestHarness
    quit*: bool
    altScreen*: bool

proc newAppRuntime*(cols, rows: int; altScreen = false): AppRuntime =
  result = AppRuntime(
    h: newTerminalTestHarness(cols, rows),
    quit: false,
    altScreen: altScreen)

proc emit(s: string) =
  if s.len == 0: return
  discard posix.write(1.cint, unsafeAddr s[0], s.len)

proc paint*(rt: AppRuntime) =
  ## Render the harness's current buffer to stdout as ANSI bytes. We
  ## emit explicit `CSI <row>;1H` cursor moves between rows rather
  ## than relying on `\n` line-feeds — libvterm's parser doesn't
  ## auto-CR on LF (LNM defaults to off), so each row needs an
  ## explicit column reset to land at col 0.
  rt.h.flush()
  let buf = rt.h.driver.buffer
  # Clear the screen first so stale glyphs from the previous paint
  # don't bleed through. CSI 2J + CSI 1;1H.
  var s = "\x1b[2J\x1b[H"
  let raw = encodeAnsi(buf)
  # Split the encodeAnsi output on '\n' (one separator per row) and
  # re-glue with explicit cursor moves so libvterm sees each row at
  # col 0.
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

proc enterAltScreen*(rt: AppRuntime) =
  ## Emit alt-screen-enter + clear so the test can observe the
  ## host-screen save behaviour.
  if rt.altScreen:
    emit("\x1b[?1049h")
    emit("\x1b[2J\x1b[H")

proc leaveAltScreen*(rt: AppRuntime) =
  if rt.altScreen:
    emit("\x1b[?1049l")

proc readKey*(timeoutMs: int = 200): string =
  ## Non-blocking single-key read. Returns "" on timeout, "<EOT>" on
  ## Ctrl+D, "<ESC>seq" for escape sequences (best effort), else a
  ## single-character string.
  var rs: TFdSet
  FD_ZERO(rs)
  FD_SET(0.cint, rs)
  var tv: Timeval
  tv.tv_sec = posix.Time(timeoutMs div 1000)
  tv.tv_usec = clong((timeoutMs mod 1000) * 1000)
  let n = posix.select(1, addr rs, nil, nil, addr tv)
  if n <= 0: return ""
  var buf: array[16, byte]
  let got = posix.read(0.cint, addr buf[0], buf.len)
  if got <= 0: return ""
  if got == 1:
    if buf[0] == 0x04: return "<EOT>"
    return $char(buf[0])
  # Multi-byte: probably an escape sequence. Surface the raw bytes so
  # the per-app handler can pattern-match on suffixes like "[A".
  result = ""
  for i in 0 ..< int(got):
    result.add char(buf[i])

proc setRawMode*() =
  ## Ensure local echo is off + canonical mode is off so the parent
  ## harness's keystrokes arrive byte-for-byte. We use `stty` via
  ## /dev/tty rather than termios.h directly to keep this helper tiny;
  ## the spawning harness configures the pty in cooked mode by
  ## default, so we toggle on the slave side.
  discard execShellCmd("stty -echo -icanon -isig min 0 time 1 < /dev/tty 2>/dev/null")

proc restoreMode*() =
  discard execShellCmd("stty sane < /dev/tty 2>/dev/null")

proc runEventLoop*(rt: AppRuntime;
                   onKey: proc(rt: AppRuntime; key: string) {.closure.}) =
  ## Generic loop. Paints once on entry, then iterates: read a key,
  ## dispatch to `onKey`, repaint, repeat until `rt.quit` is set or
  ## EOF on stdin.
  setRawMode()
  if rt.altScreen: rt.enterAltScreen()
  defer:
    if rt.altScreen: rt.leaveAltScreen()
    restoreMode()

  rt.paint()
  flushFile(stdout)

  let deadline = getMonoTime() + initDuration(seconds = 30)
  while not rt.quit and getMonoTime() < deadline:
    let key = readKey(150)
    if key == "<EOT>":
      rt.quit = true
      break
    if key.len == 0: continue
    onKey(rt, key)
    rt.paint()
    flushFile(stdout)
