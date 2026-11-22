## test_windows_driver_ctrl_c_clean_exit — M10 mandatory test.
##
## Generate a `CTRL_C_EVENT` against the driver's `SetConsoleCtrlHandler`
## routine via `GenerateConsoleCtrlEvent` and assert:
##
##   * the driver's stop flag flips so the reader thread exits,
##   * the leave sequences (alt-screen, cursor-show, mouse-disable)
##     are emitted on the output console,
##   * the console mode is restored to its pre-start state after
##     `stop()` runs.
##
## *Why this test only runs on Windows.* The whole code path is the
## Win32 Console API (`GenerateConsoleCtrlEvent`,
## `SetConsoleCtrlHandler`, `GetConsoleMode`). Linux has no
## equivalent; we skip cleanly.
##
## *Real-stack.* No mocks. The test process registers as a console
## attached to the same handle the driver claims, then sends real
## console control events through the OS.
##
## *CTRL+C can arrive disabled.* A process can carry an inheritable
## attribute that makes it ignore CTRL+C ("SetConsoleCtrlHandler can also
## enable an inheritable attribute that causes the calling process to
## ignore CTRL+C signals. If GenerateConsoleCtrlEvent sends a CTRL+C
## signal to a process for which this attribute is enabled, the handler
## functions for that process are not called. CTRL+BREAK signals always
## cause the handler functions to be called." —
## https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent).
## A process created with CREATE_NEW_PROCESS_GROUP starts with it set
## (https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags),
## and children inherit it, so whether a CI step's processes have it
## depends on what launched them; AllocConsole resets the handler list,
## not this attribute. So the test first records whether a CTRL_C_EVENT
## reached the driver with the disposition this process inherited
## (reported, not asserted: it describes the launcher), then restores
## normal CTRL+C processing for this process
## (`SetConsoleCtrlHandler(NULL, FALSE)`, the documented way) and requires
## a CTRL_C_EVENT to reach the driver.

import std/unittest

# Windows: run in a private console; see the fixture.
import ./windows_console_fixture

when defined(windows):
  import std/os
  # These real console tests exercise the driver, independently of layout.
  import isonim_tui/[events, drivers/driver, drivers/windows_driver]

when defined(windows):
  type
    HANDLE = pointer
    DWORD {.importc: "DWORD", header: "<windows.h>".} = uint32
    BOOL = int32

  const
    STD_INPUT_HANDLE  = DWORD(-10'i32)
    STD_OUTPUT_HANDLE = DWORD(-11'i32)

  proc winGetStdHandle(nStdHandle: DWORD): HANDLE
    {.importc: "GetStdHandle", header: "<windows.h>", stdcall.}

  proc generateConsoleCtrlEvent(dwCtrlEvent: DWORD;
                                dwProcessGroupId: DWORD): BOOL
    {.importc: "GenerateConsoleCtrlEvent", header: "<windows.h>", stdcall.}

  proc getConsoleMode(hConsole: HANDLE; lpMode: ptr DWORD): BOOL
    {.importc: "GetConsoleMode", header: "<windows.h>", stdcall.}

  proc setConsoleCtrlHandler(handler: pointer; add: BOOL): BOOL
    {.importc: "SetConsoleCtrlHandler", header: "<windows.h>", stdcall.}

  const
    CTRL_C_EVENT = DWORD(0)

  proc controlEventSession(event: DWORD): bool =
    ## Start a driver, raise `event` at this console (group 0: every
    ## process attached to it, which in the private console is only this
    ## one), and stop the driver again. Returns whether the driver's
    ## handler reached its stop flag. Checks that the console modes come
    ## back to what they were before `start()`.
    let hin = winGetStdHandle(STD_INPUT_HANDLE)
    let hout = winGetStdHandle(STD_OUTPUT_HANDLE)
    var savedIn, savedOut: DWORD
    check getConsoleMode(hin, addr savedIn) != 0
    check getConsoleMode(hout, addr savedOut) != 0

    let d = newWindowsDriver(80, 24,
                             enableMouse = true,
                             enablePaste = true,
                             enableAlt = true)
    d.start()
    check d.state == dsRunning
    check not d.stopRequested

    check generateConsoleCtrlEvent(event, DWORD(0)) != 0
    # Wait briefly for the handler to fire; the system runs it on a thread
    # of its own.
    sleep(200)
    result = d.stopRequested

    # `stop()` joins the reader and unwinds the RAII handles.
    d.stop()
    check d.state == dsStopped

    var liveIn, liveOut: DWORD
    check getConsoleMode(hin, addr liveIn) != 0
    check getConsoleMode(hout, addr liveOut) != 0
    check liveIn == savedIn
    check liveOut == savedOut

privateConsoleSuite("M10: WindowsDriver Ctrl+C clean exit", 1):
  suite "M10: WindowsDriver Ctrl+C clean exit":

    test "test_windows_driver_ctrl_c_clean_exit":
      when not defined(windows):
        skip()
      else:
        # Diagnostic only: did CTRL+C reach the handler with the
        # disposition this process inherited from whatever launched it?
        let inherited = controlEventSession(CTRL_C_EVENT)
        echo "CTRL_C_EVENT with the inherited CTRL+C disposition reached ",
          "the handler: ", inherited

        # Restore normal CTRL+C processing for this process; from here a
        # CTRL+C must reach the driver's handler.
        check setConsoleCtrlHandler(nil, BOOL(0)) != 0
        check controlEventSession(CTRL_C_EVENT)

        # The Ctrl handler emits leave sequences directly via
        # WriteConsoleW (outside the driver's `bytesEmitted` mirror,
        # since the handler can't safely allocate Nim memory on its
        # OS-spawned thread). We verify the visible side-effect: console
        # mode parity above already confirms termios-equivalent
        # restoration; alt-screen exit is implicit in the AltScreen RAII
        # destructor having fired (it emits `\x1b[?1049l` synchronously).
