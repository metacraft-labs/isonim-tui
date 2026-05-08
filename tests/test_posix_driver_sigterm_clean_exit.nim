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

import std/[os, posix, strutils, times, unittest]

import isonim_tui
import nim_pty

suite "M9: PosixDriver SIGTERM clean exit":

  test "test_posix_driver_sigterm_clean_exit":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var (master, slave) = openPty()
      master.setNonblock()

      let pid = posix.fork()
      check pid >= 0
      if pid == 0:
        # ----- child -----
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
        # Park here until SIGTERM arrives. nim-termctl's signal handler
        # will preempt this loop, run `restoreTerminalSafe`, and
        # re-raise SIGTERM with SIG_DFL so we die.
        while true:
          var ts = Timespec(tv_sec: posix.Time(1), tv_nsec: 0)
          discard nanosleep(ts, ts)
        # unreachable
      else:
        # ----- parent -----
        # Give the child time to enter the runtime loop; without this
        # we may send SIGTERM before nim-termctl's handler is in place.
        sleep(150)

        # Send SIGTERM. The child should die after restoring the
        # terminal.
        check kill(pid, SIGTERM) == 0

        # Drain master until the child exits.
        var output = ""
        let deadline = getTime() + initDuration(seconds = 5)
        var childReaped = false
        while getTime() < deadline:
          var buf: array[1024, byte]
          let n = posix.read(master.fd, addr buf[0], buf.len)
          if n > 0:
            var s = newString(int(n))
            for i in 0 ..< int(n): s[i] = char(buf[i])
            output.add(s)
          elif n == 0:
            break
          else:
            sleep(20)
            var status: cint
            let r = waitpid(pid, status, WNOHANG)
            if r == pid:
              childReaped = true
              # One more drain pass.
              var b2: array[1024, byte]
              let m = posix.read(master.fd, addr b2[0], b2.len)
              if m > 0:
                var s2 = newString(int(m))
                for i in 0 ..< int(m): s2[i] = char(b2[i])
                output.add(s2)
              break
        if not childReaped:
          var status: cint
          discard waitpid(pid, status, 0)

        # Verify all the leave sequences surfaced. The signal handler
        # emits these via `restoreTerminalSafe`.
        check output.contains("\x1b[?1049h")  # entered alt-screen
        check output.contains("\x1b[?1049l")  # left alt-screen
        check output.contains("\x1b[?25h")    # cursor shown
        check output.contains("\x1b[?1006l") or
              output.contains("\x1b[?1000l") # mouse disabled
        check output.contains("\x1b[?2004l")  # bracketed paste disabled
