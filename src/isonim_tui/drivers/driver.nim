## Driver concept for isonim-tui.
##
## Defines the surface every driver implementation (HeadlessDriver in
## M2, PosixDriver in M9, WindowsDriver in M10) must satisfy. Like
## `isonim/renderers/abstract_renderer.checkRendererBackend` we use a
## compile-time check helper rather than a Nim concept (concepts have
## historically had instability around `var` parameters).
##
## A driver:
##   * is started and stopped (claim / release the terminal),
##   * accepts strips from the compositor (`write(strip)`),
##   * surfaces input events from the OS (`readEvents`),
##   * is told when the surface size changes (`resize`),
##   * can be asked to flush any pending output (`flushPending`).
##
## Charter §1: drivers themselves may be `ref object` (they own OS
## handles + buffers); the data flowing through their public API is
## value-typed (`Strip`, `TerminalEvent`, `seq[byte]`).

import ../cells

type
  DriverState* = enum
    ## Lifecycle state. Drivers MUST be in `dsRunning` to accept writes
    ## or yield events; `dsStopped` is the steady starting and ending
    ## state. The compositor consults this before each paint to early-out
    ## when the driver hasn't been started.
    dsStopped
    dsStarting
    dsRunning
    dsStopping

proc surfaceCheck*[T](_: typedesc[T]): bool =
  ## Internal helper instantiated by `checkDriver`. Uses `mixin` so the
  ## driver-side procs (`start`, `stop`, `write`, `readEvents`, `resize`,
  ## `flushPending`, `state`) bind at instantiation rather than at
  ## generic-proc definition.
  mixin start, stop, write, readEvents, resize, flushPending, state
  var d: T
  var s: Strip
  when not compiles(start(d)):
    {.error: "Driver " & $T & " missing `start`".}
  when not compiles(stop(d)):
    {.error: "Driver " & $T & " missing `stop`".}
  when not compiles(write(d, s)):
    {.error: "Driver " & $T & " missing `write(d, s: Strip)`".}
  when not compiles(readEvents(d)):
    {.error: "Driver " & $T & " missing `readEvents`".}
  when not compiles(resize(d, 0, 0)):
    {.error: "Driver " & $T & " missing `resize(d, cols, rows: int)`".}
  when not compiles(flushPending(d)):
    {.error: "Driver " & $T & " missing `flushPending`".}
  when not compiles(state(d)):
    {.error: "Driver " & $T & " missing `state`".}
  true

template checkDriver*(D: typedesc): bool =
  ## Compile-time conformance check. Mirrors
  ## `checkRendererBackend[B, E]()` from isonim. Each concrete driver
  ## calls this helper near the bottom of its module via
  ## `static: doAssert checkDriver(MyDriver)` — if any required proc is
  ## missing the build fails immediately.
  surfaceCheck(D)
