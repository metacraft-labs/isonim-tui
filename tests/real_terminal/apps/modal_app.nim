## modal_app — opens a Modal on 'o', closes on 'c'. Renders a marker
## in the bottom row that flips between "modal:open" and "modal:closed".

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 10)
  var open = false

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 10)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r,
                         if open: "modal:open" else: "modal:closed",
                         width = 30)
      r.appendChild(root, lbl.node)
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
      open = true
      rebuild()
    elif key == "c" and open:
      open = false
      rebuild())
