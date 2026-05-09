## button_app — a Button widget; pressing 'a' activates it which prints
## "clicked" via the harness IPC client. 'q' quits.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6)
  var clicks = 0
  var btn: ButtonWidget
  proc onClick() =
    inc clicks

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 6)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      btn = newButton(r,
                      if clicks > 0: "clicked-" & $clicks else: "press-me",
                      width = 14, onClick = onClick)
      r.appendChild(root, btn.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "a":
      btn.activate()
      rebuild())
