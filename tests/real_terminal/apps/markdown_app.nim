## markdown_app — a Markdown widget rendering a small fixed document.

import isonim_tui
import ./app_runtime

const sample = """# Title

A paragraph with **bold** and _italic_.

- one
- two
- three
"""

when isMainModule:
  let rt = newAppRuntime(60, 14)
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let m = newMarkdown(r, source = sample, width = 50)
    r.appendChild(root, m.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q": rt.quit = true)
