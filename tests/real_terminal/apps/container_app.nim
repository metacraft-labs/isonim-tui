## container_app — a Container widget with two Static children.
## Pressing any key swaps the content; 'q' quits.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 8)
  var swap = false

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 8)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "class", "container")
      let a = newStatic(r,
                        if swap: "child-B" else: "child-A",
                        width = 18, height = 1)
      let b = newStatic(r,
                        if swap: "child-A" else: "child-B",
                        width = 18, height = 1)
      r.appendChild(root, a.node)
      r.appendChild(root, b.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    swap = not swap
    rebuild())
