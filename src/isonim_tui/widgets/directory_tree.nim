## widgets/directory_tree.nim — Tier-3b `DirectoryTree` widget (M18).
##
## Port of `textual/widgets/_directory_tree.py`. A specialisation of
## `TreeWidget` whose lazy-load callback walks a real filesystem
## directory. Children are sorted alphabetically with directories
## listed before files, matching Textual's default convention. Each
## node's `data` field carries the absolute path so consumers can
## resolve it back to a real file or directory.
##
## Filesystem reads happen through `std/os` — there is no caching
## layer between the widget and the kernel. Callers can refresh a
## subtree after creating / deleting files by calling `reload(node)`
## on the underlying tree.
##
## Charter §1: every public type is a value object except the widget
## handle (`ref`).

import std/[algorithm, os, strutils]

import ../renderer
import ../css/properties
import ./tree

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  DirectoryTreeWidget* = ref object
    tree*: TreeWidget                  ## The underlying generic Tree.
    rootPath*: string                  ## Absolute path of the root.

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc isHiddenName(name: string): bool {.inline.} =
  ## Skip dotfiles / dotdirs by default — matches Textual.
  name.len > 0 and name[0] == '.'

proc listDirectory(path: string): seq[TreeNodeRef] =
  ## Scan `path` and produce TreeNodeRef children. Directories sort
  ## first, then files; both ranges are alphabetically ordered.
  result = @[]
  if not dirExists(path): return
  var dirs: seq[(string, string)] = @[]
  var files: seq[(string, string)] = @[]
  for kind, sub in walkDir(path, relative = false):
    let name = extractFilename(sub)
    if isHiddenName(name): continue
    case kind
    of pcDir, pcLinkToDir:
      dirs.add (name, sub)
    of pcFile, pcLinkToFile:
      files.add (name, sub)
  proc cmpPair(a, b: (string, string)): int =
    cmp(a[0], b[0])
  dirs.sort(cmpPair)
  files.sort(cmpPair)
  for (name, sub) in dirs:
    let n = newTreeNode(name & "/", sub, expandable = true)
    result.add n
  for (name, sub) in files:
    let n = newTreeNode(name, sub, expandable = false)
    result.add n

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newDirectoryTree*(renderer: TerminalRenderer;
                       path: string;
                       width: int = 40;
                       viewportHeight: int = 10;
                       showRoot: bool = true;
                       border: BorderStyle = bsNone;
                       borderColor: string = "";
                       color: string = "";
                       onSelect: proc(node: TreeNodeRef) = nil
                       ): DirectoryTreeWidget =
  ## Build a DirectoryTree rooted at `path`. The root label is the
  ## final path component (or `path` itself when `path` is the root
  ## of the filesystem). Children load lazily on expansion.
  let absolute = absolutePath(path)
  var rootLabel = extractFilename(absolute)
  if rootLabel.len == 0:
    rootLabel = absolute
  if not rootLabel.endsWith("/"):
    rootLabel.add '/'
  let loader: TreeLoadProc = proc(n: TreeNodeRef): seq[TreeNodeRef] =
    listDirectory(n.data)
  let t = newTree(renderer,
    rootLabel = rootLabel,
    rootData = absolute,
    loadChildren = loader,
    width = width,
    viewportHeight = viewportHeight,
    showRoot = showRoot,
    border = border,
    borderColor = borderColor,
    color = color,
    onSelect = onSelect)
  renderer.setAttribute(t.node, "data-widget", "directory-tree")
  renderer.setAttribute(t.node, "data-path", absolute)
  DirectoryTreeWidget(tree: t, rootPath: absolute)

# ----------------------------------------------------------------------------
# Public proxies — keep callers from having to reach into `dt.tree`.
# ----------------------------------------------------------------------------

proc node*(dt: DirectoryTreeWidget): TerminalNode {.inline.} = dt.tree.node

proc root*(dt: DirectoryTreeWidget): TreeNodeRef {.inline.} = dt.tree.root

proc reloadAll*(dt: DirectoryTreeWidget) =
  ## Drop the cached children of the root and re-walk the directory.
  dt.tree.reload(dt.tree.root)

proc reloadNode*(dt: DirectoryTreeWidget; n: TreeNodeRef) =
  dt.tree.reload(n)

proc visibleLabels*(dt: DirectoryTreeWidget): seq[string] {.inline.} =
  dt.tree.visibleLabels()

proc loadCount*(dt: DirectoryTreeWidget): int {.inline.} = dt.tree.loadCount

proc cursorNode*(dt: DirectoryTreeWidget): TreeNodeRef {.inline.} =
  dt.tree.cursorNode()

proc id*(dt: DirectoryTreeWidget): int {.inline.} = dt.tree.node.id

proc expandRoot*(dt: DirectoryTreeWidget) =
  ## Convenience — expands the root so the immediate directory listing
  ## appears under the cursor.
  dt.tree.expandNode(dt.tree.root)

proc renderTree*(dt: DirectoryTreeWidget) {.inline.} = dt.tree.renderTree()
