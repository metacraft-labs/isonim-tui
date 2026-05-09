## richlog_app — a RichLog. Pressing 'a' appends a numbered line.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 10)
  var rl: RichLogWidget
  var n = 0
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    rl = newRichLog(r, width = 38, viewportHeight = 8, border = bsRound)
    rl.write("line-0")
    r.appendChild(root, rl.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "a":
      inc n
      rl.write("line-" & $n))
