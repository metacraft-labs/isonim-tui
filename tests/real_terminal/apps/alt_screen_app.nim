## alt_screen_app — enters alt-screen on launch, draws a marker,
## leaves on 'q'. The harness asserts the alt-screen-leave sequence
## in the byte stream after exit.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6, altScreen = true)
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let s = newStatic(r, "alt-marker", width = 30, height = 1)
    r.appendChild(root, s.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q": rt.quit = true)
