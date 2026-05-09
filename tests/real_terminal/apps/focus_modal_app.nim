## focus_modal_app — an Input + a Modal. Pressing 'o' opens the modal,
## 'c' closes it; characters typed go into the visible input. After a
## modal close the input should still receive characters.

import std/strutils
import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(60, 12)
  var open = false
  var buf = ""

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(60, 12)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r, "input:" & buf, width = 50)
      r.appendChild(root, lbl.node)
      let st = newLabel(r,
                        if open: "modal:open" else: "modal:closed",
                        width = 30)
      r.appendChild(root, st.node)
      root)
    if open:
      let m = newModal(rt.h, title = "Confirm", width = 24, height = 5)
      m.open()
      rt.h.flush()

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "o" and not open:
      open = true; rebuild()
    elif key == "c" and open:
      open = false; rebuild()
    elif key.len == 1 and key[0].isAlphaNumeric():
      if not open:
        buf.add key
        rebuild())
