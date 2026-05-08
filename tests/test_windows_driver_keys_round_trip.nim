## test_windows_driver_keys_round_trip — M10 mandatory test.
##
## Inject `KEY_EVENT_RECORD`s via the Win32 Console pseudo-host and
## assert the driver emits matching `KeyEvent`s on `readEvents()`.
##
## *Why this test only runs on Windows.* The whole code path is the
## Win32 Console API: `WriteConsoleInputW` (the test side) feeds the
## same record stream that `ReadConsoleInputW` (the driver side)
## consumes. Linux has no equivalent; we skip cleanly.
##
## *No mocks.* The injection path uses `WriteConsoleInputW` against
## the real STD_INPUT_HANDLE — it's the canonical "write a synthetic
## record into the console" surface, and the driver's reader thread
## decodes those records identically to what a human typing at the
## console would produce.

import std/unittest

when defined(windows):
  import std/[os, times]
  import isonim_tui

when defined(windows):
  type
    HANDLE = pointer
    DWORD = uint32
    BOOL = int32
    WORD = uint16
    WCHAR = uint16

    KeyEventRec {.importc: "KEY_EVENT_RECORD",
                  header: "<windows.h>", pure, final.} = object
      bKeyDown: BOOL
      wRepeatCount: WORD
      wVirtualKeyCode: WORD
      wVirtualScanCode: WORD
      uChar: WCHAR
      dwControlKeyState: DWORD

    InputRecord {.importc: "INPUT_RECORD",
                   header: "<windows.h>", pure, final.} = object
      eventType: WORD
      eventBlob: array[16, byte]

  const
    STD_INPUT_HANDLE = DWORD(-10'i32)
    KEY_EVENT_KIND   = WORD(0x0001)
    VK_RETURN        = WORD(0x0D)

  proc winGetStdHandle(nStdHandle: DWORD): HANDLE
    {.importc: "GetStdHandle", header: "<windows.h>", stdcall.}

  proc writeConsoleInputW(hConsole: HANDLE; lpBuffer: ptr InputRecord;
                          nLength: DWORD;
                          lpNumberOfEventsWritten: ptr DWORD): BOOL
    {.importc: "WriteConsoleInputW", header: "<windows.h>", stdcall.}

  proc makeKeyRec(vk: WORD; ch: WCHAR; ctrlState: DWORD): InputRecord =
    var rec: InputRecord
    rec.eventType = KEY_EVENT_KIND
    let kePtr = cast[ptr KeyEventRec](addr rec.eventBlob[0])
    kePtr.bKeyDown = BOOL(1)
    kePtr.wRepeatCount = WORD(1)
    kePtr.wVirtualKeyCode = vk
    kePtr.wVirtualScanCode = WORD(0)
    kePtr.uChar = ch
    kePtr.dwControlKeyState = ctrlState
    result = rec

suite "M10: WindowsDriver keys round trip":

  test "test_windows_driver_keys_round_trip":
    when not defined(windows):
      skip()
    else:
      let d = newWindowsDriver(80, 24,
                               enableMouse = false,
                               enablePaste = false,
                               enableAlt = true)
      d.start()

      let hin = winGetStdHandle(STD_INPUT_HANDLE)

      # Inject three records: 'a', Enter, Ctrl+C.
      var recs: array[3, InputRecord]
      recs[0] = makeKeyRec(WORD(ord('A')), WCHAR(ord('a')), DWORD(0))
      recs[1] = makeKeyRec(VK_RETURN, WCHAR(0), DWORD(0))
      recs[2] = makeKeyRec(WORD(ord('C')), WCHAR(3), DWORD(0x0008))
      var nwritten: DWORD = 0
      check writeConsoleInputW(hin, addr recs[0], DWORD(recs.len),
                                addr nwritten) != 0
      check int(nwritten) == 3

      # Drain events for up to 2 seconds.
      var collected: seq[TerminalEvent] = @[]
      let deadline = getTime() + initDuration(seconds = 2)
      while getTime() < deadline and collected.len < 3:
        for ev in d.readEvents():
          if ev.kind == ekKey:
            collected.add(ev)
        sleep(20)

      d.stop()

      check collected.len == 3
      check collected[0].key.key == "a"
      check collected[1].key.key == "enter"
      check collected[2].key.key == "c"
      check modCtrl in collected[2].key.modifiers
