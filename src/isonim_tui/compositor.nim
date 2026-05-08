## Compositor — initial full-repaint version (M2).
##
## Walks the renderer's `TerminalNode` tree, lays each visible node out
## as a flat row, builds a `ScreenBuffer`, and hands it to the driver.
## Dirty-region optimisation, strip caching by content hash, and the
## layered-output split land in M8; this milestone explicitly ships the
## simpler full-repaint path so every later test has a real chain to
## verify against.
##
## Layout placeholder: M3 will plug Yoga in. Until then the compositor
## treats every visible node as occupying one row of `cols` cells. Text
## nodes are flattened into the parent row; nested boxes append to the
## next row. This is enough for the M2 tests (`tdiv: text "hi"` etc.)
## and is documented as a placeholder below.

import std/[unicode]

import ./cells
import ./renderer
import ./drivers/headless_driver
import ./text/width

# Silence the spurious unused-import warning: `unicode` is used by the
# `runes(string)` iterator inside `stripFromText`; `width` is used by
# `displayWidth`. Both imports are load-bearing.

type
  Compositor* = ref object
    ## Minimal render pipeline. Owns no state beyond per-frame work
    ## buffers — the canonical state lives on the driver and the
    ## renderer's tree. We use a `ref object` for the same reason as
    ## the driver: the harness shares a single compositor between
    ## flushes.
    cols*: int
    rows*: int
    lastBuffer*: ScreenBuffer    ## Snapshot of the previous paint;
                                 ## used by introspection's
                                 ## `dirtyRegions`. Empty initially.
    lastDirty*: seq[CellRegion]

  LayoutNodeKind* = enum
    lnkText
    lnkBox

  LayoutEntry = object
    ## Flattened layout produced by the placeholder layout pass. Each
    ## entry occupies one row.
    row: int
    text: string
    nodeId: int

proc newCompositor*(cols, rows: int): Compositor =
  Compositor(
    cols: cols, rows: rows,
    lastBuffer: newScreenBuffer(cols, rows),
    lastDirty: @[])

proc resize*(c: Compositor; cols, rows: int) =
  c.cols = cols
  c.rows = rows
  c.lastBuffer = newScreenBuffer(cols, rows)
  c.lastDirty = @[]

# ----------------------------------------------------------------------------
# Placeholder layout — flat row-per-visible-node walker.
# Real layout (Yoga + cell-snap) comes in M3; this is enough to render
# the simple test trees M2 covers.
# ----------------------------------------------------------------------------

proc walkLayout(node: TerminalNode; row: var int;
                entries: var seq[LayoutEntry]) =
  ## Walk the tree and emit one layout entry per visible node. Boxes
  ## containing only text become a single text-row; nested boxes
  ## recurse and consume additional rows.
  if node == nil: return
  case node.kind
  of tnkText:
    entries.add LayoutEntry(row: row, text: node.text, nodeId: node.id)
    inc row
  of tnkBox, tnkButton, tnkInput:
    # If every child is a text node, render the box as one row whose
    # text is the concatenation. Otherwise recurse and let each child
    # claim its own row.
    var allText = node.children.len > 0
    for c in node.children:
      if c.kind != tnkText:
        allText = false
        break
    if allText:
      var s = ""
      for c in node.children:
        s.add c.text
      entries.add LayoutEntry(row: row, text: s, nodeId: node.id)
      inc row
    else:
      for c in node.children:
        walkLayout(c, row, entries)

# ----------------------------------------------------------------------------
# Cell-strip construction
# ----------------------------------------------------------------------------

proc stripFromText(text: string; cols: int): Strip =
  ## Convert a string into a Strip of exactly `cols` cells. Wide runes
  ## consume two cells (with a ghost trailing half); the row is padded
  ## with blanks to `cols`.
  var cellsAcc: seq[Cell] = @[]
  var col = 0
  for r in runes(text):
    if col >= cols: break
    let w = displayWidth(r)
    if w == 0:
      # Zero-width — combining mark. M2 places it on the same column
      # but does not yet merge it into the previous cell's grapheme;
      # M3+ revisits this with full grapheme handling integrated into
      # the layout pass.
      continue
    if w >= 2:
      if col + 1 >= cols: break
      cellsAcc.add Cell(rune: r, fg: defaultColor(), bg: defaultColor(),
                        attrs: {}, width: 2)
      cellsAcc.add ghostCell()
      col += 2
    else:
      cellsAcc.add Cell(rune: r, fg: defaultColor(), bg: defaultColor(),
                        attrs: {}, width: 1)
      col += 1
  while col < cols:
    cellsAcc.add spaceCell()
    inc col
  newStrip(cellsAcc)

proc render*(c: Compositor; root: TerminalNode): ScreenBuffer =
  ## Walk the tree, lay it out, and produce a fresh buffer.
  var buf = newScreenBuffer(c.cols, c.rows)
  if root != nil:
    var entries: seq[LayoutEntry] = @[]
    var row = 0
    walkLayout(root, row, entries)
    for entry in entries:
      if entry.row >= c.rows: continue
      buf.setRow(entry.row, stripFromText(entry.text, c.cols))
  buf

proc paint*(c: Compositor; root: TerminalNode; driver: HeadlessDriver) =
  ## Render the tree, diff against `lastBuffer` to populate
  ## `lastDirty` (introspection consumes this), then push the full
  ## buffer to the driver. The driver itself does the byte emission.
  let buf = c.render(root)
  c.lastDirty = diff(c.lastBuffer, buf)
  c.lastBuffer = buf
  driver.paintBuffer(buf)

proc layoutRegionFor*(c: Compositor; root: TerminalNode; nodeId: int):
                    tuple[row, col, width, height: int] =
  ## Look up the layout-rect of a node by id within the most recent
  ## render. Returns a zero-rect when the node didn't render. M2 returns
  ## row × full-width × 1; M3 will return real Yoga rectangles.
  result = (row: 0, col: 0, width: 0, height: 0)
  if root == nil: return
  var entries: seq[LayoutEntry] = @[]
  var row = 0
  walkLayout(root, row, entries)
  for entry in entries:
    if entry.nodeId == nodeId:
      result = (row: entry.row, col: 0, width: c.cols, height: 1)
      return

proc nodesInRenderOrder*(root: TerminalNode): seq[int] =
  ## Return ids of every node that participates in layout, in row order.
  ## Useful for introspection's `dumpTree`.
  result = @[]
  if root == nil: return
  var entries: seq[LayoutEntry] = @[]
  var row = 0
  walkLayout(root, row, entries)
  for entry in entries:
    result.add entry.nodeId

