## input_app — accepts character input and echoes it inside a Label
## prefixed with "echo:". Pressing Ctrl+D or 'enter' commits and exits.

import std/strutils
import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 5)
  var buf = ""
  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 5)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r, "echo:" & buf, width = 30)
      r.appendChild(root, lbl.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "\r" or key == "\n":
      rt.quit = true
      return
    if key.len == 1 and key[0].isAlphaNumeric():
      buf.add key
      rebuild()
      return
    if key == "q":
      rt.quit = true)
