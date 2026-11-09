## drivers/event_channel.nim — the inter-thread event queue shared by the
## threaded drivers (`PosixDriver`, `WebDriver`, `WindowsDriver`).
##
## Each driver's reader thread decodes input into `TerminalEvent` values
## and hands them to the main thread through Nim's built-in `Channel[T]`
## (https://nim-lang.org/docs/system.html#Channel). `Channel.send`
## deep-copies the payload, so under `--mm:refc` the receiver never
## touches memory another thread's heap owns, and under ARC/ORC the copy
## is still correct.
##
## The queue is owned by its driver: it is opened when the driver is
## built and released when the driver is destroyed. A `Channel` holds a
## shared-heap buffer from its first `send` until `close`, so a driver
## that only ever opened its channel leaked that buffer — and every event
## still queued in it — on destruction. LeakSanitizer reported it from
## `tests/test_posix_driver_mouse_real.nim`. The destructor below drains
## the undelivered events (destroying their payloads) and closes the
## channel. It is a no-op for a channel that was never opened, because
## `close` on zeroed memory would release a lock and condition variable
## that were never initialised.
##
## The reader thread must have been joined before the owning driver is
## destroyed; every driver's `stop` joins it first.

import ../events

type
  EventChannel* = object
    ## A driver-owned queue of decoded events. Not copyable: the
    ## underlying `Channel` is a lock plus a buffer at a fixed address,
    ## which the reader thread reaches through a `ptr EventChannel`.
    chan: Channel[TerminalEvent]
    opened: bool

proc `=copy`(dest: var EventChannel; src: EventChannel) {.error.}

proc initEventChannel*(ch: var EventChannel) =
  ## Open the queue. Called once, by the owning driver's constructor.
  open(ch.chan)
  ch.opened = true

proc pushEvent*(ch: var EventChannel; ev: TerminalEvent) =
  ## Enqueue `ev` (deep-copied) for the main thread.
  ch.chan.send(ev)

proc drainAll*(ch: var EventChannel): seq[TerminalEvent] =
  ## Every queued event, oldest first; empty when idle. Non-blocking.
  result = @[]
  while true:
    let (got, ev) = ch.chan.tryRecv()
    if not got: break
    result.add ev

proc release(ch: var EventChannel) {.raises: [].} =
  ## Drop the undelivered events, then free the channel. Must not raise:
  ## it runs inside a destructor.
  if not ch.opened: return
  try:
    discard drainAll(ch)
  except Exception:
    # Nothing here can raise in practice, and nothing could handle it
    # inside a destructor anyway. `tryRecv` raises `ValueError` only for a
    # message whose runtime type differs from the channel's ("cannot
    # receive message of wrong type"), which a `Channel[TerminalEvent]`
    # written only by `pushEvent` never holds; under refc its deep copy
    # is typed as raising the root `Exception`, hence the broad clause.
    discard
  close(ch.chan)
  ch.opened = false

# The hook signature depends on the memory manager: by value under
# ARC/ORC (`gcDestructors`), `var T` under refc, which rejects the
# by-value form. See https://nim-lang.org/docs/destructors.html
when defined(gcDestructors):
  proc `=destroy`(ch: EventChannel) =
    # `release` mutates the queue it frees. A destructor's argument is
    # the dying object itself (passed by reference, never a copy), so
    # writing through its address touches nothing anyone can observe.
    release((addr ch)[])
else:
  proc `=destroy`(ch: var EventChannel) =
    release(ch)
