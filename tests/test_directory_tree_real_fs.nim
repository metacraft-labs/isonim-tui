## test_directory_tree_real_fs — M18 mandatory test.
##
## A `DirectoryTree` pointed at the real fixture directory under
## `tests/fixtures/dir_tree/` shows the right files. Modifying the
## filesystem (creating / deleting a file inside a subdirectory) and
## reloading the affected node reflects the change.

import std/[os, sets]
import unittest
import isonim_tui

proc fixtureRoot(): string =
  currentSourcePath().parentDir / "fixtures" / "dir_tree"

suite "M18: directory tree real filesystem":
  test "test_directory_tree_real_fs":
    let path = fixtureRoot()
    let h = newTerminalTestHarness(60, 14)
    var dt: DirectoryTreeWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      dt = newDirectoryTree(r, path = path,
        width = 40, viewportHeight = 12)
      r.appendChild(root, dt.node)
      root)

    # Only the root row is visible before expansion.
    check dt.visibleLabels().len == 1
    check dt.loadCount == 0

    # Expand the root: scan happens against the real filesystem.
    let p = newPilot(h)
    p.focus(dt.node)
    p.press("right")
    check dt.loadCount == 1

    let topLevel = dt.visibleLabels().toHashSet
    # Directories first (suffixed with "/"), then files. We don't pin
    # ordering of the synthetic root label, but we do require the four
    # top-level entries to be present.
    check "docs/" in topLevel
    check "src/" in topLevel
    check "README.md" in topLevel
    check "config.toml" in topLevel

    # Walk the cursor down to "src/" and expand it.
    var sawSrc = false
    for _ in 0 ..< 8:
      let n = dt.cursorNode()
      if n != nil and n.label == "src/":
        sawSrc = true
        break
      p.press("down")
    check sawSrc
    p.press("right")
    let srcLabels = dt.visibleLabels().toHashSet
    check "main.nim" in srcLabels
    check "sub/" in srcLabels

    # Mutate the filesystem: drop a fresh file under src/ and reload the
    # `src/` node. After reload the new file is visible without
    # reconstructing the widget.
    let newFile = path / "src" / "added_at_runtime.txt"
    writeFile(newFile, "hello\n")
    defer: discard tryRemoveFile(newFile)

    # Find the src/ node directly off the root.
    var srcNode: TreeNodeRef = nil
    for c in dt.root.children:
      if c.label == "src/":
        srcNode = c
        break
    check srcNode != nil

    dt.reloadNode(srcNode)
    h.flush()
    let afterAdd = dt.visibleLabels().toHashSet
    check "added_at_runtime.txt" in afterAdd
    check "main.nim" in afterAdd

    # Remove it and reload again — the node disappears from the
    # tree's visible-row set.
    discard tryRemoveFile(newFile)
    dt.reloadNode(srcNode)
    h.flush()
    let afterRemove = dt.visibleLabels().toHashSet
    check "added_at_runtime.txt" notin afterRemove
    check "main.nim" in afterRemove

    h.dispose()
