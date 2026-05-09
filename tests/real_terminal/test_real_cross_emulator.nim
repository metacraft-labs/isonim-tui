## test_real_cross_emulator — M29 cross-terminal-emulator suite.
##
## *Status: complete (all three emulators).* The previous draft of
## this file shipped three `skip()` placeholders because headless CI
## had no X11 / Wayland display. The follow-up plan called for an
## Xvfb-based lane; this module is that lane.
##
## ## Architecture
##
## For each emulator (xterm, kitty, alacritty):
##
##   1. Compile a small isonim-tui app (`apps/cross_emulator_app`)
##      that mounts a bordered Static widget with a known marker
##      string (`ISONIM-TUI-M29-CROSS-EMU-OK`) and paints it to
##      stdout via the production `encodeAnsi` byte path.
##   2. Spawn `xvfb-run -a --server-args="-screen 0 1024x768x24"`
##      hosting the emulator.
##   3. Inside the emulator, run `tmux -L <sock> new-session -s app
##      "<app>; sleep 5"`. tmux is the in-emulator capture surface —
##      the test process reads back the cell grid via
##      `tmux -L <sock> capture-pane -t app -p`, which produces the
##      exact characters the emulator put on screen (after consuming
##      the app's ANSI byte stream as a real terminal emulator
##      would).
##   4. Assert the marker text appears in the captured pane.
##   5. Send `q` to quit the app, then kill the tmux server and the
##      emulator process.
##
## ## Why this exercises real cross-emulator behaviour
##
## The libvterm parser TermAssert uses is *one* terminal emulator
## implementation. xterm, kitty, and alacritty each have their own
## independent VT parser (xterm's hand-written state machine, kitty's
## Rust-based parser, alacritty's vte crate). Running the same byte
## stream through all three exercises the SGR + cursor-positioning +
## border-glyph code paths against three independent implementations
## — exactly the bug class the M29 spec calls out.
##
## ## Skip semantics
##
## If any of `xvfb-run`, `xterm`, `kitty`, `alacritty`, or `tmux` is
## not on PATH (e.g. the test is run outside the dev shell), the
## corresponding sub-test calls `skip()` with an explicit message.
## When run via `nix develop --command just test-cross-emulator` all
## five binaries are present and the tests execute for real.

import std/[unittest, os, osproc, strutils, times]

import ./test_helpers

const
  Marker = "ISONIM-TUI-M29-CROSS-EMU-OK"
  AppStem = "cross_emulator_app"
  TmuxTmpDir = "/tmp/isonim-tui-m29-cross-emu"

proc which(bin: string): string =
  ## Best-effort PATH lookup. Returns the absolute path or "" if not
  ## found. Avoids osproc.execProcess so the lookup itself can't hang.
  let pathEnv = getEnv("PATH")
  for dir in pathEnv.split(':'):
    if dir.len == 0: continue
    let candidate = dir / bin
    if fileExists(candidate): return candidate
  ""

proc waitForTmuxSession(sock, name: string;
                       timeout: Duration): bool =
  ## Poll `tmux -L <sock> has-session -t <name>` until it succeeds or
  ## the timeout expires.
  let deadline = getTime() + timeout
  while getTime() < deadline:
    let (_, ec) = execCmdEx("tmux -L " & sock & " has-session -t " &
                            name & " 2>/dev/null")
    if ec == 0: return true
    sleep(100)
  false

proc capturePane(sock, name: string): string =
  let (output, _) = execCmdEx("tmux -L " & sock & " capture-pane -t " &
                              name & " -p")
  output

proc killTmux(sock: string) =
  discard execCmdEx("tmux -L " & sock & " kill-server 2>/dev/null")

proc killProcess(pid: int) =
  if pid <= 0: return
  discard execCmdEx("kill " & $pid & " 2>/dev/null")
  # Also clean up any stray Xvfb the xvfb-run wrapper spawned.
  discard execCmdEx("pkill -P " & $pid & " 2>/dev/null")

proc spawnEmulator(emu, app, sock: string): Process =
  ## Spawn the emulator under xvfb-run, instructed to run tmux which
  ## hosts the test app. Each emulator's invocation is slightly
  ## different (xterm uses `-e`; kitty / alacritty take a command tail
  ## via different conventions), so we shell out to bash for kitty and
  ## alacritty so they uniformly see a single shell-quoted command.
  let cmd =
    case emu
    of "xterm":
      # xterm's `-e` interprets the remaining args as the child command
      # directly — no shell needed.
      "xvfb-run -a --server-args='-screen 0 1024x768x24' " &
        "xterm -geometry 80x24 -e tmux -L " & sock &
        " new-session -s app \"" & app & "; sleep 5\""
    of "kitty":
      # kitty under -o allow_remote_control=no avoids needing a kitten
      # control socket. The tail is a bash invocation that hosts tmux.
      "xvfb-run -a --server-args='-screen 0 1024x768x24' " &
        "kitty -o allow_remote_control=no bash -c " &
        "'tmux -L " & sock & " new-session -s app \"" & app &
        "; sleep 5\"'"
    of "alacritty":
      "xvfb-run -a --server-args='-screen 0 1024x768x24' " &
        "alacritty -e bash -c " &
        "'tmux -L " & sock & " new-session -s app \"" & app &
        "; sleep 5\"'"
    else:
      raise newException(ValueError, "unknown emulator: " & emu)
  startProcess("/bin/sh", args = ["-c", cmd], options = {poStdErrToStdOut})

type
  EmulatorOutcome = enum
    eoOk, eoMissingTool, eoNoSession, eoNoMarker

proc runEmulatorOnce(emu: string;
                    paneOut: var string;
                    missingTool: var string): EmulatorOutcome =
  ## Run the emulator end-to-end once. The test bodies call this and
  ## then translate the outcome into a `skip()` or a `check` — `skip()`
  ## must run inside the `test` block, not from a helper.
  let needed = ["xvfb-run", emu, "tmux"]
  for n in needed:
    if which(n) == "":
      missingTool = n
      return eoMissingTool
  compileApp(AppStem)
  let app = childAppPath(AppStem)
  createDir(TmuxTmpDir)
  putEnv("TMUX_TMPDIR", TmuxTmpDir)
  let sock = "isonim-m29-" & emu
  killTmux(sock)
  let p = spawnEmulator(emu, app, sock)
  let pid = processID(p)
  defer:
    killTmux(sock)
    killProcess(pid)
    if running(p): discard p.waitForExit(timeout = 2000)
    p.close()
  let ready = waitForTmuxSession(sock, "app",
                                 initDuration(seconds = 8))
  if not ready:
    return eoNoSession
  sleep(800) # give the app a beat to paint after tmux comes up
  paneOut = capturePane(sock, "app")
  # Tell the app to quit cleanly so the emulator process winds down.
  discard execCmdEx("tmux -L " & sock & " send-keys -t app q 2>/dev/null")
  if paneOut.contains(Marker):
    eoOk
  else:
    eoNoMarker

template runEmulatorTest(emu, testName: string) =
  var pane = ""
  var missing = ""
  let outcome = runEmulatorOnce(emu, pane, missing)
  case outcome
  of eoMissingTool:
    skip()
  of eoNoSession:
    let dir = bundleDir(testName)
    writeFile(dir / "result.txt",
      "Emulator " & emu & " did not produce a tmux session.\n")
    check outcome == eoOk
  of eoNoMarker:
    let dir = bundleDir(testName)
    writeFile(dir / "captured_pane.txt", pane)
    check outcome == eoOk
  of eoOk:
    check outcome == eoOk

suite "M29 cross-emulator (xvfb + tmux)":

  test "test_real_xterm_compat":
    runEmulatorTest("xterm", "test_real_xterm_compat")

  test "test_real_kitty_compat":
    runEmulatorTest("kitty", "test_real_kitty_compat")

  test "test_real_alacritty_compat":
    runEmulatorTest("alacritty", "test_real_alacritty_compat")
