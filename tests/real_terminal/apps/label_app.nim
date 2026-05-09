## label_app — renders a Label and toggles its text on key.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 4)
  var lbl: LabelWidget
  var on = false
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    lbl = newLabel(r, "label-initial", width = 30)
    r.appendChild(root, lbl.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    on = not on
    lbl.setText(if on: "label-toggled" else: "label-initial"))
