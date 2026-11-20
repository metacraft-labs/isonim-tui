## Test support for the PosixDriver tests that run against a real pty.
##
## Two helpers, both used from the test thread:
##
## * `PtyMasterDrain` reads the master side of a pty continuously on its
##   own thread, the way a terminal emulator does, and keeps what it read.
##   A test that writes to the slave and only reads the master later
##   deadlocks on macOS. There `tcsetattr(TCSAFLUSH)` (and `TCSADRAIN`)
##   first waits until the slave's output queue is empty, and a pty's
##   output queue is emptied only by a read on the master. In xnu
##   (apple-oss-distributions/xnu, read at f6217f89): `bsd/kern/tty.c`,
##   `ttioctl_locked`, cases `TIOCSETAW`/`TIOCSETAF`, call `ttywait()`,
##   which sleeps while `t_outq.c_cc` is non-zero, with no limit when
##   `t_timeout` is 0; `bsd/kern/tty_dev.c`, `ptcread`, the master's read,
##   is what takes bytes off `t_outq` (`q_to_b`). POSIX states the rule
##   for TCSAFLUSH: "the change shall occur after all output written to
##   fildes is transmitted"
##   (https://pubs.opengroup.org/onlinepubs/9799919799/functions/tcsetattr.html).
##   The driver's `stop()` writes its leave sequences and then restores
##   termios with `TCSAFLUSH`, so a test that has not read them yet never
##   gets past `stop()`.
##   On Linux the pty layer hands slave output straight to the master's
##   buffer, so the queue is always empty and the same test passes there.
##
## * `PhaseWatchdog` turns a hang into a failure that names where it hung.
##   The test names each phase as it enters it; if one phase runs longer
##   than the budget, the watchdog writes the test and phase to stderr and
##   ends the process with exit status 1. It does not retry and does not
##   extend anything: a phase over budget is a failed test.
##
## MOCK POLICY: no mocks. The pty is real; these helpers only read it and
## watch the clock.

import std/[locks, monotimes, os, posix, strutils, times]

const
  DrainCapacity = 256 * 1024
    ## Bytes kept from the master. The driver tests write a few hundred.
  PhaseNameCapacity = 96

type
  DrainState = object
    lock: Lock
    fd: cint
    stop: bool
    len: int
    overflowed: bool
    readError: cint
    bytes: array[DrainCapacity, char]

  PtyMasterDrain* = object
    ## Continuous reader of a pty master. Create with `startMasterDrain`,
    ## end with `stopMasterDrain`.
    state: ptr DrainState
    thread: Thread[ptr DrainState]

  WatchdogState = object
    lock: Lock
    disarmed: bool
    budgetNs: int64
    phaseStartNs: int64
    phaseLen: int
    phase: array[PhaseNameCapacity, char]
    testLen: int
    test: array[PhaseNameCapacity, char]

  PhaseWatchdog* = object
    ## Fails the process when one phase of a test exceeds its budget.
    state: ptr WatchdogState
    thread: Thread[ptr WatchdogState]

proc drainLoop(s: ptr DrainState) {.thread.} =
  # Non-blocking reads with a short sleep, not poll(2): Apple's poll(2)
  # man page lists under BUGS that "The poll() system call currently does
  # not support devices", and a pty master is a device.
  var buf: array[4096, char]
  while true:
    withLock s.lock:
      if s.stop: break
    let n = posix.read(s.fd, addr buf[0], buf.len)
    if n > 0:
      withLock s.lock:
        let room = DrainCapacity - s.len
        let take = min(int(n), room)
        if take > 0:
          copyMem(addr s.bytes[s.len], addr buf[0], take)
          s.len += take
        if take < int(n):
          s.overflowed = true
    elif n == 0:
      sleep(5)  # no slave open yet, or it closed; keep watching
    else:
      let e = errno
      if e == EAGAIN or e == EWOULDBLOCK or e == EINTR:
        sleep(5)
      elif e == EIO:
        # A master reads EIO once no slave descriptor is open (Linux);
        # the test may open one again, so keep going.
        sleep(5)
      else:
        withLock s.lock:
          s.readError = e
        break

proc startMasterDrain*(masterFd: cint): PtyMasterDrain =
  ## Start reading `masterFd` on a new thread. The descriptor is switched
  ## to non-blocking mode.
  let fl = fcntl(masterFd, F_GETFL)
  if fl < 0 or fcntl(masterFd, F_SETFL, fl or O_NONBLOCK) < 0:
    raiseOSError(osLastError(), "fcntl(O_NONBLOCK) on the pty master")
  result.state = createShared(DrainState)
  initLock(result.state.lock)
  result.state.fd = masterFd
  createThread(result.thread, drainLoop, result.state)

proc output*(d: PtyMasterDrain): string =
  ## Everything read from the master so far.
  withLock d.state.lock:
    if d.state.readError != 0:
      raise newException(IOError, "reading the pty master failed: " &
        $strerror(d.state.readError))
    if d.state.overflowed:
      raise newException(IOError, "the pty master produced more than " &
        $DrainCapacity & " bytes")
    result = newString(d.state.len)
    if d.state.len > 0:
      copyMem(addr result[0], addr d.state.bytes[0], d.state.len)

proc waitForOutput*(d: PtyMasterDrain; needle: string;
                    timeout: Duration): bool =
  ## Wait until `needle` has been read from the master, or `timeout`.
  let deadline = getMonoTime() + timeout
  while true:
    if needle in d.output: return true
    if getMonoTime() >= deadline: return false
    sleep(5)

proc stopMasterDrain*(d: var PtyMasterDrain) =
  ## Stop and join the reader thread. Idempotent.
  if d.state == nil: return
  withLock d.state.lock:
    d.state.stop = true
  joinThread(d.thread)
  deinitLock(d.state.lock)
  freeShared(d.state)
  d.state = nil

proc copyName(dst: var array[PhaseNameCapacity, char]; dstLen: var int;
              src: string) =
  dstLen = min(src.len, PhaseNameCapacity)
  for i in 0 ..< dstLen: dst[i] = src[i]

proc nowNs(): int64 = getMonoTime().ticks

proc watchdogLoop(s: ptr WatchdogState) {.thread.} =
  while true:
    sleep(50)
    var expired = false
    var msg: string
    withLock s.lock:
      if s.disarmed: break
      let elapsed = nowNs() - s.phaseStartNs
      if elapsed > s.budgetNs:
        expired = true
        var test = newString(s.testLen)
        for i in 0 ..< s.testLen: test[i] = s.test[i]
        var phase = newString(s.phaseLen)
        for i in 0 ..< s.phaseLen: phase[i] = s.phase[i]
        msg = "\n" & test & ": WATCHDOG: phase '" & phase &
          "' did not finish within " & $(s.budgetNs div 1_000_000_000) &
          " s; it is blocked. Failing the test.\n"
    if expired:
      discard posix.write(STDERR_FILENO, cstring(msg), msg.len)
      # `_exit`, not `quit`: the stuck thread may hold the terminal, and
      # atexit handlers that touch it could block exactly like the phase.
      exitnow(1)

proc startPhaseWatchdog*(testName: string; perPhase: Duration;
                         firstPhase: string): PhaseWatchdog =
  ## Start watching. Each phase, starting with `firstPhase`, may take at
  ## most `perPhase`.
  result.state = createShared(WatchdogState)
  initLock(result.state.lock)
  result.state.budgetNs = perPhase.inNanoseconds
  copyName(result.state.test, result.state.testLen, testName)
  copyName(result.state.phase, result.state.phaseLen, firstPhase)
  result.state.phaseStartNs = nowNs()
  createThread(result.thread, watchdogLoop, result.state)

proc phase*(w: PhaseWatchdog; name: string) =
  ## Enter phase `name`; its budget starts now.
  withLock w.state.lock:
    copyName(w.state.phase, w.state.phaseLen, name)
    w.state.phaseStartNs = nowNs()

proc stopPhaseWatchdog*(w: var PhaseWatchdog) =
  ## Disarm and join. Idempotent.
  if w.state == nil: return
  withLock w.state.lock:
    w.state.disarmed = true
  joinThread(w.thread)
  deinitLock(w.state.lock)
  freeShared(w.state)
  w.state = nil
