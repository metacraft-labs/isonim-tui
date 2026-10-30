## test_windows_driver_resize — M10 mandatory test.
##
## Inject a `WINDOW_BUFFER_SIZE_RECORD` via `WriteConsoleInputW` and
## assert the driver surfaces a `ResizeEvent` with the matching
## (cols, rows). Mirrors `test_posix_driver_resize_real` but uses the
## structured-record path instead of SIGWINCH.
##
## *Why this test only runs on Windows.* The injection surface is the
## Win32 Console API. Linux has no equivalent; we skip cleanly.

import std/unittest

when defined(windows):
  import std/[os, times]
  # These real console tests exercise the driver, independently of layout.
  import isonim_tui/[events, drivers/driver, drivers/windows_driver]

when defined(windows):
  type
    HANDLE = pointer
    DWORD {.importc: "DWORD", header: "<windows.h>".} = uint32
    BOOL = int32
    WORD = uint16
    SHORT = int16

    CoordRec {.importc: "COORD", header: "<windows.h>", pure, final.} = object
      x {.importc: "X".}: SHORT
      y {.importc: "Y".}: SHORT

    WindowBufferSizeRec {.importc: "WINDOW_BUFFER_SIZE_RECORD",
                           header: "<windows.h>", pure, final.} = object
      dwSize: CoordRec

    KeyEventStorage {.importc: "KEY_EVENT_RECORD",
                       header: "<windows.h>", pure, final.} = object
    MouseEventStorage {.importc: "MOUSE_EVENT_RECORD",
                         header: "<windows.h>", pure, final.} = object
    InputEventPayload {.union, bycopy.} = object
      keyEvent: KeyEventStorage
      mouseEvent: MouseEventStorage
      windowSizeEvent: WindowBufferSizeRec

    InputRecord {.importc: "INPUT_RECORD",
                   header: "<windows.h>", pure, final.} = object
      eventType {.importc: "EventType".}: WORD
      eventBlob {.importc: "Event".}: InputEventPayload

  const
    STD_INPUT_HANDLE = DWORD(-10'i32)
    WINDOW_BUFFER_SIZE_KIND = WORD(0x0004)

  proc winGetStdHandle(nStdHandle: DWORD): HANDLE
    {.importc: "GetStdHandle", header: "<windows.h>", stdcall.}

  proc writeConsoleInputW(hConsole: HANDLE; lpBuffer: ptr InputRecord;
                          nLength: DWORD;
                          lpNumberOfEventsWritten: ptr DWORD): BOOL
    {.importc: "WriteConsoleInputW", header: "<windows.h>", stdcall.}

  proc makeResizeRec(cols, rows: int): InputRecord =
    var rec: InputRecord
    rec.eventType = WINDOW_BUFFER_SIZE_KIND
    let wePtr = cast[ptr WindowBufferSizeRec](addr rec.eventBlob)
    wePtr.dwSize.x = SHORT(cols)
    wePtr.dwSize.y = SHORT(rows)
    result = rec

suite "M10: WindowsDriver resize":

  test "test_windows_driver_resize":
    when not defined(windows):
      skip()
    else:
      let d = newWindowsDriver(80, 24,
                               enableMouse = false,
                               enablePaste = false,
                               enableAlt = false)
      d.start()

      let hin = winGetStdHandle(STD_INPUT_HANDLE)
      var rec = makeResizeRec(132, 50)
      var nwritten: DWORD = 0
      check writeConsoleInputW(hin, addr rec, DWORD(1), addr nwritten) != 0
      check int(nwritten) == 1

      var sawResize = false
      var seenCols = 0
      var seenRows = 0
      let deadline = getTime() + initDuration(seconds = 2)
      while getTime() < deadline:
        for ev in d.readEvents():
          if ev.kind == ekResize:
            sawResize = true
            seenCols = ev.resize.cols
            seenRows = ev.resize.rows
            break
        if sawResize: break
        sleep(20)

      check sawResize
      check seenCols == 132
      check seenRows == 50

      # Apply the resize so the driver's view of (cols, rows) tracks
      # the host. After this call a subsequent paint cycle would
      # render at the new dimensions.
      d.resize(seenCols, seenRows)
      check d.cols == 132
      check d.rows == 50

      d.stop()
