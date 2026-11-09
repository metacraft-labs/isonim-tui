## drivers/stop_flag.nim — the "please exit" flag a threaded driver's
## `stop` raises for its reader thread.
##
## The drivers used to share a plain `bool` between the two threads. That
## is a data race — undefined behaviour in the C the compiler emits, and
## ThreadSanitizer reported it between `PosixDriver.stop` and the reader
## loop (tests/test_posix_driver_real_pty.nim). The flag is now an
## `Atomic[bool]` (https://nim-lang.org/docs/atomics.html): `request`
## publishes with release ordering and `requested` observes with acquire
## ordering, so whatever the stopping thread wrote before asking is
## visible to the reader once it sees the request.
##
## A driver owns its flag inside its `ref object`, so the address handed
## to the reader thread (`addr d.stopFlag`) stays valid until the driver's
## `stop` has joined that thread.

import std/atomics

type
  StopFlag* = object
    value: Atomic[bool]

proc clear*(flag: var StopFlag) =
  ## Reset before (re)starting the reader thread.
  flag.value.store(false, moRelease)

proc request*(flag: var StopFlag) =
  ## Ask the reader thread to exit at its next check.
  flag.value.store(true, moRelease)

proc requested*(flag: ptr StopFlag): bool =
  ## Whether `request` has been called since the last `clear`. Called
  ## from the reader thread through the pointer it was started with.
  flag[].value.load(moAcquire)
