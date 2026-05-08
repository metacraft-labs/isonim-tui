## test_posix_driver_panic_restores_terminal — M9 mandatory test.
##
## Force a panic in the runtime loop while the driver is running.
## The expectation: the terminal state observable to the host (slave
## termios + alt-screen state) is restored to its pre-start state by
## the time the process exits.
##
## *Why fork.* Two halves of the panic-safe restoration story live in
## different places:
##
##   1. `nim-termctl` installs an `atexit` hook on first
##      `enableRawMode`; that hook runs `restoreTerminalSafe` which
##      uses async-signal-safe `tcsetattr` + `write(2)` to leave
##      alt-screen, drop mouse mode, show the cursor, and reset
##      termios.
##   2. The same `RawMode`/`AltScreen`/...  destructors fire during
##      stack unwind on a normal exception, restoring on the way out.
##
## We can't test `atexit` from inside our own test process (it runs
## on quit, which would kill the test runner). The pattern we use
## here is the one nim-pty's `test_pty_signals` uses: `fork` a child,
## exercise the panic in the child, observe restoration from the
## parent. This is a real-stack integration test — no mocks — that
## confirms the M9 driver's claim "terminal restored even on panic".

import std/[os, posix, strutils, times, unittest]

import isonim_tui
import nim_pty

# Importc the libc `exit` so atexit hooks fire (the std/posix
# `exitnow` is `_exit`, which deliberately skips atexit).
proc cLibcExit(status: cint) {.importc: "exit", header: "<stdlib.h>".}

suite "M9: PosixDriver panic-safe restoration":

  test "test_posix_driver_panic_restores_terminal":
    when not defined(linux) and not defined(macosx):
      skip()
    else:
      var (master, slave) = openPty()
      master.setNonblock()

      let pid = posix.fork()
      check pid >= 0
      if pid == 0:
        # ----- child -----
        # Become our own session leader so signals stay local and the
        # parent test runner isn't disturbed by anything we send.
        discard setsid()
        # nim-termctl's `restoreTerminalSafe` writes its leave
        # sequences to STDOUT_FILENO (fd 1). Dup the slave onto the
        # standard FDs so all restoration bytes flow into our pty
        # rather than the parent test runner's inherited stdout.
        discard dup2(slave.fd, 0)
        discard dup2(slave.fd, 1)
        discard dup2(slave.fd, 2)
        # Run the driver against the slave FD; raise an uncaught
        # exception inside the runtime loop. nim-termctl's atexit
        # hook + the RawMode destructor on stack unwind will both
        # fire; either path emits alt-screen-leave + cursor-show on
        # the slave's output which the parent can observe via master.
        try:
          let d = newPosixDriver(80, 24,
                                 inputFd = 0,
                                 outputFd = 1,
                                 enableMouse = true,
                                 enablePaste = false,
                                 enableAlt = true)
          d.start()
          # Force a panic that propagates out of the "runtime loop".
          raise newException(ValueError, "synthetic runtime panic")
        except CatchableError:
          # We deliberately do NOT call `d.stop()` — `d` was scoped to
          # the `try` block and has already been swept up. The point
          # of this test is that nim-termctl's atexit hook restores
          # the terminal even without explicit cleanup. Use libc
          # `exit(3)` (NOT `_exit`) so atexit handlers fire.
          discard
        cLibcExit(cint(1))
      else:
        # ----- parent -----
        # Drain everything the child wrote until it exits. Set up a
        # short timeout per read so the loop converges within the
        # 5-second test budget.
        var output = ""
        let deadline = getTime() + initDuration(seconds = 5)
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
            # Reap to detect child exit.
            var status: cint
            let r = waitpid(pid, status, WNOHANG)
            if r == pid:
              # Child exited — drain any remaining bytes once more.
              var b2: array[1024, byte]
              let m = posix.read(master.fd, addr b2[0], b2.len)
              if m > 0:
                var s2 = newString(int(m))
                for i in 0 ..< int(m): s2[i] = char(b2[i])
                output.add(s2)
              break
        # Make sure the child is reaped.
        var status: cint
        discard waitpid(pid, status, 0)

        # The driver should have entered alt-screen + hidden cursor +
        # enabled mouse capture on `start()`, then on the way down
        # (whether via stack-unwind destructors or the atexit hook)
        # emitted the leave-alt-screen + show-cursor + leave-mouse
        # sequences.
        check output.contains("\x1b[?1049h")  # entered alt-screen
        check output.contains("\x1b[?1049l")  # left alt-screen
        check output.contains("\x1b[?25h")    # cursor shown again
        # Mouse-mode disable (one of the two forms emitted).
        check output.contains("\x1b[?1006l") or
              output.contains("\x1b[?1000l")
