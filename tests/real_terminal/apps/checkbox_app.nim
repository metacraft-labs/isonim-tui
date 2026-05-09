## checkbox_app — a Checkbox widget.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6)
  var checked = false
  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 6)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let cb = newCheckbox(r, label = "agree", value = checked)
      r.appendChild(root, cb.node)
      let lbl = newLabel(r,
                         if checked: "state:checked" else: "state:unchecked",
                         width = 30)
      r.appendChild(root, lbl.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "t":
      checked = not checked
      rebuild())
