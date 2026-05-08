## test_tree_snapshot_coverage — M18 snapshot deliverable.
##
## Four fixtures pinning the visual states: a collapsed root / a single
## expansion / a two-level expansion / a deeply-nested expansion. The
## tree shape is deterministic — children come from a hand-built
## `loadChildren` closure rather than the filesystem so the goldens are
## stable across runs and platforms.

import unittest
import isonim_tui

proc buildLoader(): TreeLoadProc =
  ## Synthetic, hand-shaped tree:
  ##
  ##   root
  ##     project/
  ##       src/
  ##         core/
  ##           engine.nim
  ##           types.nim
  ##         main.nim
  ##       README.md
  ##     scripts/
  ##       build.sh
  result = proc(n: TreeNodeRef): seq[TreeNodeRef] =
    case n.label
    of "root":
      @[
        newTreeNode("project/", "project", expandable = true),
        newTreeNode("scripts/", "scripts", expandable = true)
      ]
    of "project/":
      @[
        newTreeNode("src/", "project/src", expandable = true),
        newTreeNode("README.md", "project/README.md")
      ]
    of "src/":
      @[
        newTreeNode("core/", "project/src/core", expandable = true),
        newTreeNode("main.nim", "project/src/main.nim")
      ]
    of "core/":
      @[
        newTreeNode("engine.nim", "project/src/core/engine.nim"),
        newTreeNode("types.nim",  "project/src/core/types.nim")
      ]
    of "scripts/":
      @[newTreeNode("build.sh", "scripts/build.sh")]
    else:
      @[]

proc mkTree(h: TerminalTestHarness): TreeWidget =
  let loader = buildLoader()
  var t: TreeWidget
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    t = newTree(r,
      rootLabel = "root",
      rootData = "root",
      loadChildren = loader,
      width = 30,
      viewportHeight = 10)
    r.appendChild(root, t.node)
    root)
  t

suite "M18: tree snapshot coverage":

  test "tree_collapsed_root":
    let h = newTerminalTestHarness(40, 12)
    discard mkTree(h)
    discard h.snap("m18_tree_collapsed_root")
    h.dispose()

  test "tree_one_expansion":
    let h = newTerminalTestHarness(40, 12)
    let t = mkTree(h)
    t.expandNode(t.root)
    h.flush()
    discard h.snap("m18_tree_one_expansion")
    h.dispose()

  test "tree_two_level":
    let h = newTerminalTestHarness(40, 12)
    let t = mkTree(h)
    t.expandNode(t.root)
    let project = t.root.children[0]   # project/
    t.expandNode(project)
    h.flush()
    discard h.snap("m18_tree_two_level")
    h.dispose()

  test "tree_deeply_nested":
    let h = newTerminalTestHarness(40, 12)
    let t = mkTree(h)
    t.expandNode(t.root)
    let project = t.root.children[0]    # project/
    t.expandNode(project)
    let src = project.children[0]       # src/
    t.expandNode(src)
    let core = src.children[0]          # core/
    t.expandNode(core)
    let scripts = t.root.children[1]    # scripts/
    t.expandNode(scripts)
    h.flush()
    discard h.snap("m18_tree_deeply_nested")
    h.dispose()
