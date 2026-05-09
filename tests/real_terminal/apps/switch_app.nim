## switch_app — a Switch widget; toggles via 't'.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6)
  var sw: SwitchWidget
  var marker = "off"

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 6)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sw = newSwitch(r, value = (marker == "on"))
      r.appendChild(root, sw.node)
      let lbl = newLabel(r, "marker:" & marker, width = 30)
      r.appendChild(root, lbl.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "t":
      marker = if marker == "off": "on" else: "off"
      rebuild())
