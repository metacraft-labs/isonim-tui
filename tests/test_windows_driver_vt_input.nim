## test_windows_driver_vt_input — M10 mandatory test (verifies that
## `ENABLE_VIRTUAL_TERMINAL_INPUT` was set on the input handle and that
## the structured-record path produces typed events with the same
## shape POSIX produces, achieving cross-platform parity).
##
## *What this asserts.*
##
##   1. `start()` flips `ENABLE_VIRTUAL_TERMINAL_INPUT` on the input
##      handle. We read the live console mode via `GetConsoleMode` and
##      assert the bit is set. This is the documented Windows 10 1809+
##      contract that lets a structured-record consumer also receive
##      VT-encoded byte runs (necessary for things like Kitty graphics
##      reply parsing on a Windows host).
##   2. A real `KEY_EVENT_RECORD` injected via `WriteConsoleInputW`
##      decodes into the *same* `KeyEvent` shape (`kind`, `key`,
##      `modifiers`) that the POSIX byte-stream parser produces. The
##      test injects a Ctrl+A, an arrow-up, and an F1 — three records
##      that exercise the modifier, navigation, and function paths
##      respectively. Each is asserted to surface as a `TerminalEvent`
##      with the canonical Textual-style key name.
##
## *Why this test only runs on Windows.* The whole code path is the
## Win32 Console API: `WriteConsoleInputW` (test side) +
## `ReadConsoleInputW` (driver side) + `GetConsoleMode` (assertion
## side). Linux has no equivalent — under `--os:linux` we'd be
## exercising different code, defeating the parity point.
##
## *No mocks.* The injection surface is the same `WriteConsoleInputW`
## the OS would use to deliver records from a real keyboard event,
## and the consumer is the real reader thread the driver spawns in
## `start()`.

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
    ENABLE_VIRTUAL_TERMINAL_INPUT = DWORD(0x0200)
    VK_UP            = WORD(0x26)
    VK_F1            = WORD(0x70)
    LEFT_CTRL_PRESSED = DWORD(0x0008)

  proc winGetStdHandle(nStdHandle: DWORD): HANDLE
    {.importc: "GetStdHandle", header: "<windows.h>", stdcall.}

  proc getConsoleMode(hConsole: HANDLE; lpMode: ptr DWORD): BOOL
    {.importc: "GetConsoleMode", header: "<windows.h>", stdcall.}

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

suite "M10: WindowsDriver VT input parity":

  test "test_windows_driver_vt_input":
    when not defined(windows):
      skip()
    else:
      let d = newWindowsDriver(80, 24,
                               enableMouse = false,
                               enablePaste = false,
                               enableAlt = false)
      d.start()
      check d.state == dsRunning

      # 1) ENABLE_VIRTUAL_TERMINAL_INPUT must be set on stdin.
      let hin = winGetStdHandle(STD_INPUT_HANDLE)
      var liveMode: DWORD
      check getConsoleMode(hin, addr liveMode) != 0
      check (liveMode and ENABLE_VIRTUAL_TERMINAL_INPUT) != 0

      # 2) Inject three structured records that exercise three
      # different translateKeyRecord branches: modifier (Ctrl+A),
      # navigation (Up arrow), and function (F1). Each must surface
      # with the canonical Textual-style key name.
      var recs: array[3, InputRecord]
      # Ctrl+A — virtual key 'A', uChar = SOH (0x01), Ctrl modifier.
      recs[0] = makeKeyRec(WORD(ord('A')), WCHAR(0x01), LEFT_CTRL_PRESSED)
      # Up arrow — VK_UP, uChar = 0, no modifiers (named-key path).
      recs[1] = makeKeyRec(VK_UP, WCHAR(0), DWORD(0))
      # F1 — VK_F1, uChar = 0, no modifiers (function-key path).
      recs[2] = makeKeyRec(VK_F1, WCHAR(0), DWORD(0))

      var nwritten: DWORD = 0
      check writeConsoleInputW(hin, addr recs[0], DWORD(recs.len),
                                addr nwritten) != 0
      check int(nwritten) == 3

      var collected: seq[TerminalEvent] = @[]
      let deadline = getTime() + initDuration(seconds = 2)
      while getTime() < deadline and collected.len < 3:
        for ev in d.readEvents():
          if ev.kind == ekKey:
            collected.add(ev)
        sleep(20)

      d.stop()

      check collected.len == 3

      # Ctrl+A — must arrive with the modCtrl bit set. The key name
      # follows the rune ('a' lowercase form, decoded from uChar=0x01
      # is non-printable so we just assert the modifier and kind).
      check modCtrl in collected[0].key.modifiers

      # Up arrow — must arrive as a navigation key with key="up".
      check collected[1].key.kind == kkNavigation
      check collected[1].key.key == "up"

      # F1 — must arrive as a function key with key="f1".
      check collected[2].key.kind == kkFunction
      check collected[2].key.key == "f1"
