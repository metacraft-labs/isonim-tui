## loading_app — a LoadingIndicator widget; pressing space steps the
## animation frame.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 4)
  var li: LoadingIndicatorWidget
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    li = newLoadingIndicator(r, label = "loading")
    r.appendChild(root, li.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == " " or key == "n":
      li.tickFrame())
