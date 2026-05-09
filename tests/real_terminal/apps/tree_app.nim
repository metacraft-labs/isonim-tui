## tree_app — a Tree with synchronously-loaded children. 'e' expands
## the focused node, 'c' collapses it, 'j'/'k' navigate.

import isonim_tui
import ./app_runtime

when isMainModule:
  let rt = newAppRuntime(40, 12)
  var t: TreeWidget
  proc loader(node: TreeNodeRef): seq[TreeNodeRef] =
    if node.label == "root":
      result.add newTreeNode("alpha", expandable = false)
      result.add newTreeNode("beta", expandable = true)
      result.add newTreeNode("gamma", expandable = false)
    elif node.label == "beta":
      result.add newTreeNode("beta-1", expandable = false)
      result.add newTreeNode("beta-2", expandable = false)

  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    t = newTree(r, rootLabel = "root", loadChildren = loader,
                width = 30, viewportHeight = 9, border = bsRound)
    r.appendChild(root, t.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    case key
    of "e": t.expandNode(t.cursorNode())
    of "c": t.collapseNode(t.cursorNode())
    of "j": t.moveDown()
    of "k": t.moveUp()
    else: discard)
