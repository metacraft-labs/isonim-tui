## test_posix_driver_sigterm_clean_exit — M9 mandatory test.
##
## SIGTERM triggers a clean shutdown — alt-screen exited, cursor
## visible, termios restored. nim-termctl installs SIGINT/SIGTERM/
## SIGHUP/SIGQUIT handlers on the first `enableRawMode`; those run
## an async-signal-safe `restoreTerminalSafe` that
##
##   * leaves alt-screen   (`CSI ?1049l`)
##   * disables mouse mode (`CSI ?1006l CSI ?1000l`)
##   * disables paste / focus (when active)
##   * shows the cursor    (`CSI ?25h`)
##   * restores termios via `tcsetattr`
##
## then re-raises the signal with `SIG_DFL` so the process actually
## dies. We exercise that path by forking a child, starting the
## driver inside it, and sending SIGTERM from the parent.
##
## *When to send it.* The handlers exist only once `d.start()` has run
## `enableRawMode`; a SIGTERM before that meets the default action and
## the child dies having written nothing. The parent used to guess with a
## fixed 150 ms sleep, which a slow debug build on a loaded macOS runner
## overran. The child now writes one byte on a pipe after `d.start()`
## returns, and the parent sends SIGTERM only after reading it, within a
## deadline. A failed `fork` fails the test before any signal is sent:
## pid -1 must never reach `kill(2)`, where it means every process this
## user may signal.
##
## The parent reads the master from the moment the child exists
## (`PtyMasterDrain`, started after `fork` so the child never inherits its
## thread): on macOS the restore's `tcsetattr(TCSAFLUSH)` waits until the
## output already written has been read (see `pty_test_support.nim`). A
## `PhaseWatchdog` fails the test, naming the phase, if any phase blocks.

import std/[posix, strutils, times, unittest]

import isonim_tui
import nim_pty

import ./pty_test_support

suite "M9: PosixDriver SIGTERM clean exit":

  test "test_posix_driver_sigterm_clean_exit":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var (master, slave) = openPty()
      # The child reports "d.start() returned" on this pipe.
      var ready: array[2, cint]
      check posix.pipe(ready) == 0

      let pid = posix.fork()
      if pid < 0:
        # Without a child there is nothing to signal, and pid -1 must never
        # reach kill(2): kill(-1, sig) signals every process this user may
        # signal. Fail here, with the reason.
        let err = errno
        checkpoint "fork failed: " & $strerror(err)
        discard posix.close(ready[0])
        discard posix.close(ready[1])
        fail()
      elif pid == 0:
        # ----- child -----
        discard posix.close(ready[0])
        # New session so signals stay local to us.
        discard setsid()
        # nim-termctl's async-signal-safe restoration path writes to
        # `STDOUT_FILENO` (fd 1) explicitly — that's where it expects
        # the host terminal to live. Dup the slave onto fd 1 (and 0
        # for symmetry) before starting the driver so the restoration
        # bytes flow into our pty instead of the parent test runner's
        # inherited stdout.
        discard dup2(slave.fd, 0)
        discard dup2(slave.fd, 1)
        discard dup2(slave.fd, 2)
        let d = newPosixDriver(80, 24,
                               inputFd = 0,
                               outputFd = 1,
                               enableMouse = true,
                               enablePaste = true,
                               enableAlt = true)
        d.start()
        # The handlers are installed and every mode is on: tell the parent.
        var b = 'R'
        discard posix.write(ready[1], addr b, 1)
        discard posix.close(ready[1])
        # Park here until SIGTERM arrives. nim-termctl's signal handler
        # will preempt this loop, run `restoreTerminalSafe`, and
        # re-raise SIGTERM with SIG_DFL so we die.
        while true:
          var ts = Timespec(tv_sec: posix.Time(1), tv_nsec: 0)
          discard nanosleep(ts, ts)
        # unreachable
      else:
        # ----- parent -----
        discard posix.close(ready[1])
        var wd = startPhaseWatchdog("test_posix_driver_sigterm_clean_exit",
                                    initDuration(seconds = 20),
                                    "wait for the child's d.start()")
        defer: stopPhaseWatchdog(wd)
        var drain = startMasterDrain(master.fd)
        defer: stopMasterDrain(drain)

        # Wait for the child's byte, at most `ReadyBudget`. A child that dies
        # first closes the pipe and the read returns 0; one that hangs before
        # writing is killed here rather than left behind. select(2) on a pipe
        # (not a device, so it is reliable on macOS too).
        const ReadyBudget = initDuration(seconds = 10)
        let readyBy = getTime() + ReadyBudget
        var got = -1
        var b: char
        while got < 0 and getTime() < readyBy:
          var rs: TFdSet
          FD_ZERO(rs)
          FD_SET(ready[0], rs)
          var tv = Timeval(tv_sec: posix.Time(0), tv_usec: Suseconds(50_000))
          if select(ready[0] + 1, addr rs, nil, nil, addr tv) > 0:
            got = int(posix.read(ready[0], addr b, 1))
        discard posix.close(ready[0])
        checkpoint "readiness byte: read returned " & $got
        if got == 1 and b == 'R':
          # Send SIGTERM. The child should die after restoring the
          # terminal.
          wd.phase("SIGTERM and wait for the child to exit")
          check kill(pid, SIGTERM) == 0
          var status: cint
          check waitpid(pid, status, 0) == pid
          # It died of the re-raised SIGTERM, not of something else.
          check WIFSIGNALED(status)
          check WTERMSIG(status) == SIGTERM

          # Verify all the leave sequences surfaced. The signal handler
          # emits these via `restoreTerminalSafe`; the restore wrote them
          # before the child died, but the drain may still be reading, so
          # wait for each one (the cursor is shown last, after the paste
          # disable: waiting for one sequence alone raced the next).
          wd.phase("read the restore bytes")
          for needle in ["\x1b[?1049l", "\x1b[?2004l", "\x1b[?25h"]:
            discard drain.waitForOutput(needle, initDuration(seconds = 5))
          let output = drain.output
          checkpoint "master output: " & output.repr
          check output.contains("\x1b[?1049h")  # entered alt-screen
          check output.contains("\x1b[?1049l")  # left alt-screen
          check output.contains("\x1b[?25h")    # cursor shown
          check output.contains("\x1b[?1006l") or
                output.contains("\x1b[?1000l") # mouse disabled
          check output.contains("\x1b[?2004l")  # bracketed paste disabled
        else:
          # Not ready (dead, or stuck before writing): do not send SIGTERM
          # into an unknown state. Kill it so nothing is left running.
          discard kill(pid, SIGKILL)
          var status: cint
          discard waitpid(pid, status, 0)
          fail()
