## listview_app — a ListView with five items; 'j'/'k' move highlight.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 10)
  var hl = 0
  let items = @[ListItem(label: "one"), ListItem(label: "two"),
                ListItem(label: "three"), ListItem(label: "four"),
                ListItem(label: "five")]

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(40, 10)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let lv = newListView(r, items = items, width = 30, viewportHeight = 7,
                           border = bsRound)
      lv.setHighlight(hl)
      r.appendChild(root, lv.node)
      let lbl = newLabel(r, "hl:" & items[hl].label, width = 30)
      r.appendChild(root, lbl.node)
      root)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "j" and hl < items.len - 1: inc hl; rebuild()
    elif key == "k" and hl > 0: dec hl; rebuild())
