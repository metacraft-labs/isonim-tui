## widgets/tree.nim — Tier-3b `Tree` widget (M18).
##
## Port of `textual/widgets/tree.py` (~1,601 LOC) — pragmatic core.
## A hierarchical tree with lazy children, expand / collapse, and
## arrow-glyph indicators. Navigation:
##
##   * Up / Down       — move highlight to previous / next visible node
##   * Left            — collapse current node (or move to parent)
##   * Right           — expand current node (loads lazily) and move
##                       to the first child if already expanded
##   * Enter / Space   — toggle expand/collapse (and trigger lazy load)
##   * Home / End      — jump to first / last visible node
##
## The lazy-load contract: a node has an `expandable` flag (true when
## the user supplies a `loadChildren` callback or pre-populates
## children). The first time a node expands the widget calls
## `loadChildren(node)` exactly once and caches the returned children
## on the node. Subsequent expansions reuse the cached children — the
## `loaded` flag prevents re-invoking the loader. Collapsing does not
## clear the cache; reload is explicit via `reload(node)`.
##
## Glyphs follow Textual's convention:
##   ▶  collapsed branch with children
##   ▼  expanded branch
##   (space)  leaf
##
## Charter §1: every public type is a value object except the widget
## handle (`ref`) and the `TreeNodeRef` (also `ref`, because nodes
## form a parent / child object graph that the user mutates).

import std/strutils

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  TreeNodeRef* = ref object
    ## A single tree node. `label` is the visible string. `data` is an
    ## opaque user payload (e.g. a filesystem path for `DirectoryTree`).
    ## `expandable` distinguishes branches (can hold children) from
    ## leaves. `loaded` flips to true after the first lazy load.
    label*: string
    data*: string
    expandable*: bool
    expanded*: bool
    loaded*: bool
    children*: seq[TreeNodeRef]
    parent*: TreeNodeRef

  TreeLoadProc* = proc(node: TreeNodeRef): seq[TreeNodeRef] {.closure.}
    ## User-supplied lazy children loader. Returns the children for the
    ## given node. Invoked exactly once per node, the first time the
    ## node expands.

  TreeWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    root*: TreeNodeRef
    showRoot*: bool                     ## When false, the synthetic
                                        ## root is hidden and only its
                                        ## children render.
    width*: int
    viewportHeight*: int
    scrollY*: int
    cursor*: int                        ## Index into the flattened
                                        ## visible-row list. -1 = none.
    border*: BorderStyle
    borderColor*: string
    color*: string
    loadChildren*: TreeLoadProc
    onExpand*: proc(node: TreeNodeRef)
    onCollapse*: proc(node: TreeNodeRef)
    onSelect*: proc(node: TreeNodeRef)
    loadCount*: int                     ## How many times `loadChildren`
                                        ## was invoked. Tests assert on
                                        ## this to confirm laziness.

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------

proc renderTree*(t: TreeWidget)
proc expandNode*(t: TreeWidget; n: TreeNodeRef)
proc collapseNode*(t: TreeWidget; n: TreeNodeRef)
proc toggleNode*(t: TreeWidget; n: TreeNodeRef)
proc moveDown*(t: TreeWidget)
proc moveUp*(t: TreeWidget)
proc moveLeft*(t: TreeWidget)
proc moveRight*(t: TreeWidget)
proc moveHome*(t: TreeWidget)
proc moveEnd*(t: TreeWidget)
proc activateCurrent*(t: TreeWidget)
proc reload*(t: TreeWidget; n: TreeNodeRef)

# ----------------------------------------------------------------------------
# Node construction helpers (public — used by DirectoryTree and tests)
# ----------------------------------------------------------------------------

proc newTreeNode*(label: string; data: string = "";
                  expandable: bool = false): TreeNodeRef =
  ## Build a fresh tree node. `expandable` should be `true` for branches
  ## that may hold children (even if the children list is empty until
  ## the first lazy load).
  TreeNodeRef(
    label: label, data: data,
    expandable: expandable,
    expanded: false, loaded: false,
    children: @[], parent: nil)

proc addChild*(parent, child: TreeNodeRef) =
  ## Attach `child` to `parent`. Sets the back-pointer.
  child.parent = parent
  parent.children.add child
  if not parent.expandable:
    parent.expandable = true

# ----------------------------------------------------------------------------
# Visible-row flattening
# ----------------------------------------------------------------------------

type
  VisibleRow = object
    node: TreeNodeRef
    depth: int

proc flattenVisible(t: TreeWidget): seq[VisibleRow] =
  ## Walk the tree top-down emitting every node that is currently
  ## visible (i.e. an ancestor chain of expanded nodes leads to it).
  ## When `showRoot` is false the root itself is hidden but its
  ## children render at depth 0.
  result = @[]
  if t.root == nil: return
  proc walk(n: TreeNodeRef; depth: int; rows: var seq[VisibleRow]) =
    rows.add VisibleRow(node: n, depth: depth)
    if n.expanded:
      for c in n.children:
        walk(c, depth + 1, rows)
  if t.showRoot:
    walk(t.root, 0, result)
  else:
    if t.root.expanded:
      for c in t.root.children:
        walk(c, 0, result)

# ----------------------------------------------------------------------------
# Glyph helpers
# ----------------------------------------------------------------------------

proc nodeGlyph(n: TreeNodeRef): string =
  ## Return the prefix glyph for `n` based on expandable + expanded.
  if not n.expandable: return "  "
  if n.expanded: return "\xE2\x96\xBC "  # ▼ + space
  "\xE2\x96\xB6 "                         # ▶ + space

proc indentFor(depth: int): string =
  ## Two ASCII spaces per depth level. Cell-aware — every level adds
  ## width 2 regardless of the eventual border / glyph rendering.
  if depth <= 0: return ""
  result = newString(depth * 2)
  for i in 0 ..< depth * 2:
    result[i] = ' '

# ----------------------------------------------------------------------------
# Render
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "";
             reverse: bool = false; dim: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  if dim:
    r.setStyle(box, "italic", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc ensureScroll(t: TreeWidget; visibleCount: int) =
  if t.viewportHeight <= 0: return
  if t.cursor < 0: return
  if t.cursor < t.scrollY:
    t.scrollY = t.cursor
  let bottom = t.scrollY + t.viewportHeight - 1
  if t.cursor > bottom:
    t.scrollY = t.cursor - t.viewportHeight + 1
  if t.scrollY < 0: t.scrollY = 0
  let maxScroll = max(0, visibleCount - t.viewportHeight)
  if t.scrollY > maxScroll: t.scrollY = maxScroll

proc renderTree*(t: TreeWidget) =
  let r = t.renderer
  clearTreeChildren(r, t.node)
  let glyphs = bordersGlyphs(t.border)
  let useBorder = t.border != bsNone
  let body = max(1, t.width)
  if useBorder:
    emitRow(r, t.node, topBorderRow(glyphs, body), t.borderColor)
  let rows = flattenVisible(t)
  ensureScroll(t, rows.len)
  let visible = max(0, min(rows.len - t.scrollY, t.viewportHeight))
  for i in 0 ..< visible:
    let absIdx = t.scrollY + i
    let row = rows[absIdx]
    let prefix = indentFor(row.depth) & nodeGlyph(row.node)
    let line = prefix & row.node.label
    let padded = padOrTruncate(line, body)
    let isCursor = absIdx == t.cursor
    let painted =
      if useBorder: glyphs.left & padded & glyphs.right
      else: padded
    emitRow(r, t.node, painted, t.color, isCursor)
  for _ in visible ..< t.viewportHeight:
    let blank = spaces(body)
    let painted =
      if useBorder: glyphs.left & blank & glyphs.right
      else: blank
    emitRow(r, t.node, painted, t.borderColor)
  if useBorder:
    emitRow(r, t.node, bottomBorderRow(glyphs, body), t.borderColor)

# ----------------------------------------------------------------------------
# Cursor helpers
# ----------------------------------------------------------------------------

proc cursorNode*(t: TreeWidget): TreeNodeRef =
  ## Return the node currently under the cursor, or nil.
  let rows = flattenVisible(t)
  if t.cursor < 0 or t.cursor >= rows.len: return nil
  rows[t.cursor].node

proc indexOf(rows: seq[VisibleRow]; n: TreeNodeRef): int =
  for i, r in rows:
    if r.node == n: return i
  -1

proc setCursorTo*(t: TreeWidget; n: TreeNodeRef) =
  let rows = flattenVisible(t)
  let idx = indexOf(rows, n)
  if idx >= 0:
    t.cursor = idx
    t.renderTree()

# ----------------------------------------------------------------------------
# Expand / collapse
# ----------------------------------------------------------------------------

proc loadChildrenIfNeeded(t: TreeWidget; n: TreeNodeRef) =
  ## Invoke the user's `loadChildren` callback exactly once per node.
  ## If `n` already has its `loaded` flag set the callback is skipped —
  ## even if `children` was emptied externally, the user owns the cache
  ## and should call `reload(n)` explicitly to re-trigger the load.
  if n.loaded: return
  n.loaded = true
  if t.loadChildren == nil: return
  let kids = t.loadChildren(n)
  inc t.loadCount
  for c in kids:
    addChild(n, c)

proc expandNode*(t: TreeWidget; n: TreeNodeRef) =
  if n == nil: return
  if not n.expandable: return
  if n.expanded: return
  loadChildrenIfNeeded(t, n)
  n.expanded = true
  if t.onExpand != nil: t.onExpand(n)
  t.renderTree()

proc collapseNode*(t: TreeWidget; n: TreeNodeRef) =
  if n == nil: return
  if not n.expanded: return
  n.expanded = false
  if t.onCollapse != nil: t.onCollapse(n)
  t.renderTree()

proc toggleNode*(t: TreeWidget; n: TreeNodeRef) =
  if n == nil: return
  if n.expanded: t.collapseNode(n)
  else: t.expandNode(n)

proc reload*(t: TreeWidget; n: TreeNodeRef) =
  ## Drop any cached children on `n` and clear its `loaded` flag so the
  ## next expansion re-invokes `loadChildren`. Used by DirectoryTree to
  ## refresh after filesystem changes.
  if n == nil: return
  for c in n.children:
    c.parent = nil
  n.children.setLen(0)
  n.loaded = false
  if n.expanded:
    n.expanded = false
    t.expandNode(n)
  else:
    t.renderTree()

# ----------------------------------------------------------------------------
# Keyboard navigation
# ----------------------------------------------------------------------------

proc moveDown*(t: TreeWidget) =
  let rows = flattenVisible(t)
  if rows.len == 0: return
  if t.cursor < 0:
    t.cursor = 0
  elif t.cursor < rows.len - 1:
    inc t.cursor
  t.renderTree()

proc moveUp*(t: TreeWidget) =
  let rows = flattenVisible(t)
  if rows.len == 0: return
  if t.cursor < 0:
    t.cursor = 0
  elif t.cursor > 0:
    dec t.cursor
  t.renderTree()

proc moveLeft*(t: TreeWidget) =
  ## Collapse the current node if it's expanded; otherwise jump to the
  ## parent. Mirrors Textual's behaviour.
  let n = t.cursorNode()
  if n == nil: return
  if n.expanded:
    t.collapseNode(n)
    return
  if n.parent != nil:
    let parent = n.parent
    # When the synthetic root is hidden, don't park the cursor on it.
    if (not t.showRoot) and parent == t.root: return
    t.setCursorTo(parent)

proc moveRight*(t: TreeWidget) =
  ## Expand the current node (lazy-load); if already expanded, descend
  ## to the first child.
  let n = t.cursorNode()
  if n == nil: return
  if n.expandable and not n.expanded:
    t.expandNode(n)
    return
  if n.expanded and n.children.len > 0:
    t.setCursorTo(n.children[0])

proc moveHome*(t: TreeWidget) =
  let rows = flattenVisible(t)
  if rows.len == 0: return
  t.cursor = 0
  t.renderTree()

proc moveEnd*(t: TreeWidget) =
  let rows = flattenVisible(t)
  if rows.len == 0: return
  t.cursor = rows.len - 1
  t.renderTree()

proc activateCurrent*(t: TreeWidget) =
  let n = t.cursorNode()
  if n == nil: return
  if n.expandable:
    t.toggleNode(n)
  if t.onSelect != nil:
    t.onSelect(n)
  fireEvent(t.node, "tree-select")

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTree*(renderer: TerminalRenderer;
              rootLabel: string;
              rootData: string = "";
              loadChildren: TreeLoadProc = nil;
              width: int = 30;
              viewportHeight: int = 8;
              showRoot: bool = true;
              border: BorderStyle = bsNone;
              borderColor: string = "";
              color: string = "";
              onExpand: proc(node: TreeNodeRef) = nil;
              onCollapse: proc(node: TreeNodeRef) = nil;
              onSelect: proc(node: TreeNodeRef) = nil): TreeWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "tree")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "tree")
  let root = newTreeNode(rootLabel, rootData, expandable = true)
  let t = TreeWidget(
    renderer: renderer, node: node,
    root: root,
    showRoot: showRoot,
    width: max(1, width),
    viewportHeight: max(1, viewportHeight),
    scrollY: 0,
    cursor: 0,
    border: border, borderColor: borderColor, color: color,
    loadChildren: loadChildren,
    onExpand: onExpand,
    onCollapse: onCollapse,
    onSelect: onSelect,
    loadCount: 0)
  t.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    let lower = ev.key.key.toLowerAscii
    case lower
    of "down", "arrowdown":             t.moveDown()
    of "up", "arrowup":                 t.moveUp()
    of "left", "arrowleft":             t.moveLeft()
    of "right", "arrowright":           t.moveRight()
    of "home":                          t.moveHome()
    of "end":                           t.moveEnd()
    of "enter", "return", "space":      t.activateCurrent()
    else: discard)
  t

# ----------------------------------------------------------------------------
# Convenience accessors (for tests + DirectoryTree)
# ----------------------------------------------------------------------------

proc id*(t: TreeWidget): int {.inline.} = t.node.id

proc visibleRowCount*(t: TreeWidget): int {.inline.} =
  flattenVisible(t).len

proc visibleLabels*(t: TreeWidget): seq[string] =
  ## Snapshot helper: the labels of the currently visible rows in
  ## top-down order. Tests use this for laziness assertions.
  result = @[]
  for r in flattenVisible(t):
    result.add r.node.label

proc childrenOf*(n: TreeNodeRef): seq[TreeNodeRef] {.inline.} = n.children
