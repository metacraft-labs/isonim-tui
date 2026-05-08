## test_tree_expand_lazy — M18 mandatory test.
##
## Expanding a node calls the user's `loadChildren` proc once; loaded
## children persist until collapse. The harness `eventLog` records the
## keydown that triggered the expansion. A second expand of the same
## node is a no-op — the cached children are reused.

import unittest
import isonim_tui

suite "M18: tree lazy expansion":
  test "test_tree_expand_lazy":
    let h = newTerminalTestHarness(40, 12)
    var tree: TreeWidget
    var loadCalls: seq[string] = @[]
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let loader: TreeLoadProc = proc(n: TreeNodeRef): seq[TreeNodeRef] =
        loadCalls.add n.label
        case n.label
        of "root":
          @[
            newTreeNode("alpha", "alpha", expandable = true),
            newTreeNode("beta",  "beta",  expandable = false)
          ]
        of "alpha":
          @[newTreeNode("alpha-leaf", "alpha-leaf")]
        else:
          @[]
      tree = newTree(r,
        rootLabel = "root",
        rootData = "root",
        loadChildren = loader,
        width = 30, viewportHeight = 8)
      r.appendChild(root, tree.node)
      root)

    # Initial state: root visible, no load yet.
    check loadCalls.len == 0
    check tree.loadCount == 0
    check tree.visibleLabels() == @["root"]

    let p = newPilot(h)
    p.focus(tree.node)

    # Press Right to expand the root → loadChildren fires once.
    p.press("right")
    check loadCalls.len == 1
    check loadCalls == @["root"]
    check tree.loadCount == 1
    check tree.visibleLabels() == @["root", "alpha", "beta"]

    # Move cursor to "alpha" (expand stays the same — Right on a
    # collapsed expandable node expands it; alpha now is collapsed).
    p.press("down")
    check tree.cursorNode().label == "alpha"

    # Expand alpha → second loadChildren call.
    p.press("right")
    check loadCalls.len == 2
    check loadCalls[1] == "alpha"
    check tree.loadCount == 2
    check tree.visibleLabels() == @["root", "alpha", "alpha-leaf", "beta"]

    # Collapse alpha (Left). loadChildren must NOT fire again.
    p.press("left")
    check loadCalls.len == 2
    check tree.loadCount == 2
    check tree.visibleLabels() == @["root", "alpha", "beta"]

    # Re-expand alpha — children persist; loader is *not* re-invoked.
    p.press("right")
    check loadCalls.len == 2
    check tree.loadCount == 2
    check tree.visibleLabels() == @["root", "alpha", "alpha-leaf", "beta"]

    # The harness eventLog recorded the keydowns. At minimum the focus
    # event and several keydowns are present.
    let log = h.eventLog()
    var keydownCount = 0
    var sawFocus = false
    for e in log:
      if e.eventType == "keydown" and e.targetId == tree.node.id:
        inc keydownCount
      if e.eventType == "focus" and e.targetId == tree.node.id:
        sawFocus = true
    check sawFocus
    # We pressed Right, Down, Right, Left, Right — five keydowns
    # routed at the tree.
    check keydownCount == 5

    h.dispose()

  test "tree_collapse_keeps_cached_children":
    let h = newTerminalTestHarness(40, 8)
    var tree: TreeWidget
    var loadCalls = 0
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let loader: TreeLoadProc = proc(n: TreeNodeRef): seq[TreeNodeRef] =
        inc loadCalls
        @[
          newTreeNode("one"),
          newTreeNode("two"),
          newTreeNode("three")
        ]
      tree = newTree(r,
        rootLabel = "branch",
        rootData = "branch",
        loadChildren = loader,
        width = 20, viewportHeight = 6)
      r.appendChild(root, tree.node)
      root)

    let p = newPilot(h)
    p.focus(tree.node)
    p.press("right")
    check loadCalls == 1
    check tree.root.children.len == 3
    p.press("left")
    p.press("right")
    p.press("left")
    p.press("right")
    # Three additional toggles, but loader still ran exactly once.
    check loadCalls == 1
    check tree.root.children.len == 3
    h.dispose()

  test "tree_reload_re_invokes_loader":
    let h = newTerminalTestHarness(40, 8)
    var tree: TreeWidget
    var loadCalls = 0
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let loader: TreeLoadProc = proc(n: TreeNodeRef): seq[TreeNodeRef] =
        inc loadCalls
        @[newTreeNode("dynamic-" & $loadCalls)]
      tree = newTree(r,
        rootLabel = "root",
        rootData = "root",
        loadChildren = loader,
        width = 20, viewportHeight = 4)
      r.appendChild(root, tree.node)
      root)

    let p = newPilot(h)
    p.focus(tree.node)
    p.press("right")
    check loadCalls == 1
    check tree.visibleLabels() == @["root", "dynamic-1"]

    # `reload` drops the cache and re-expands.
    tree.reload(tree.root)
    h.flush()
    check loadCalls == 2
    check tree.visibleLabels() == @["root", "dynamic-2"]
    h.dispose()
