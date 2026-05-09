## static_app — renders a Static widget with bordered text. Pressing
## any key cycles the displayed text. 'q' or Ctrl+D exits.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6)
  var idx = 0
  let labels = ["hello-static", "second-line", "third-line"]
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let s = newStatic(r, labels[idx], width = 30, height = 3,
                      border = bsRound)
    r.appendChild(root, s.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    idx = (idx + 1) mod labels.len
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 6)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let s = newStatic(r, labels[idx], width = 30, height = 3,
                        border = bsRound)
      r.appendChild(root, s.node)
      root))
