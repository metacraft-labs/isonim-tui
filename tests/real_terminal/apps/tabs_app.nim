## tabs_app — a Tabs widget; arrow keys cycle.

import std/strutils
import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 6)
  var idx = 0
  let tabs = @[Tab(id: "alpha", label: "alpha"),
               Tab(id: "beta", label: "beta"),
               Tab(id: "gamma", label: "gamma")]

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 6)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let t = newTabs(r, tabs = tabs, activeIndex = idx, width = 30)
      r.appendChild(root, t.node)
      let lbl = newLabel(r, "active:" & tabs[idx].label, width = 30)
      r.appendChild(root, lbl.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key.contains("[C") or key == "n":
      idx = (idx + 1) mod tabs.len
      rebuild()
    elif key.contains("[D") or key == "p":
      idx = (idx + tabs.len - 1) mod tabs.len
      rebuild())
