## textarea_app — a TextArea. Letters insert a character, 'U' undoes,
## 'q' quits.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 8)
  var ta: TextAreaWidget
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    ta = newTextArea(r, text = "start", width = 30, viewportHeight = 5,
                     maxUndoDepth = 32)
    r.appendChild(root, ta.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "U":
      ta.undo()
      return
    if key.len == 1 and key[0] >= 'a' and key[0] <= 'z':
      ta.insertText(key))
