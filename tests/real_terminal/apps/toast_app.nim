## toast_app — shows a Toast on 's'. The harness observes the toast
## body in the rendered frame.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 8)
  var shown = false

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 8)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lbl = newLabel(r,
                         if shown: "toast:visible" else: "toast:hidden",
                         width = 30)
      r.appendChild(root, lbl.node)
      root)
    if shown:
      let t = newToast(rt.h, title = "saved",
                       body = "ok", durationMs = 60_000.0)
      t.show()
      rt.h.flush()

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "s" and not shown:
      shown = true
      rebuild()
    elif key == "h" and shown:
      shown = false
      rebuild())
