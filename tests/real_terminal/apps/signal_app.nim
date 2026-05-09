## signal_app — installs a SIGINT handler that exits with 130. Used by
## `test_real_signal_handling`.

import std/posix
import isonim_tui
import ./app_runtime

proc cExit(code: cint) {.importc: "_exit", header: "<unistd.h>".}

proc onSig(sig: cint) {.noconv.} =
  let m = "got-sigint\r\n"
  discard write(1.cint, unsafeAddr m[0], m.len)
  cExit(130)

when isMainModule:
  let rt = newAppRuntime(40, 6)
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let s = newStatic(r, "ready-for-signal", width = 30, height = 1)
    r.appendChild(root, s.node)
    root)
  signal(SIGINT, onSig)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q": rt.quit = true)
