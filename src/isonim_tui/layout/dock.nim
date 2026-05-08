## Docking layout pass.
##
## Port of Textual's `textual/_dock.py`. A docked child is removed from
## its parent's main-axis flow and pinned to one of the parent's edges
## (left / right / top / bottom). The remaining children share whatever
## space is left after the docks have claimed theirs.
##
## Algorithm (single-pass):
##
##   1. Walk children, separate them into `docks` (with edge + size) and
##      `flow` (regular children).
##   2. Compute each dock's rectangle by carving slices off the parent
##      rect on the appropriate edge.
##   3. The remaining inner rectangle is the *content area* — flow
##      children are laid out inside it (their layout policy applies
##      there).

import ./terminal_layout

type
  DockEdge* = enum
    deLeft
    deRight
    deTop
    deBottom

  DockSpec* = object
    handle*: int64
    edge*: DockEdge
    size*: int    ## Cells of width (Left/Right) or height (Top/Bottom).

  DockResult* = object
    ## Output of a dock pass: each docked child's rect, plus the inner
    ## (content) area for the rest of the children.
    rects*: seq[CellRect]
    inner*: CellRect

proc applyDocks*(parent: CellRect; docks: openArray[DockSpec]): DockResult =
  ## Compute the docked rectangles and the remaining inner content area.
  ##
  ## Docks are applied in the order given. Each dock subtracts from the
  ## current inner rect — so two `Top`-docked children stack vertically
  ## from the parent's top edge.
  var rects = newSeq[CellRect](docks.len)
  var inner = parent
  for i, d in docks:
    case d.edge
    of deLeft:
      let w = min(d.size, inner.width)
      rects[i] = CellRect(col: inner.col, row: inner.row,
                          width: w, height: inner.height)
      inner = CellRect(col: inner.col + w, row: inner.row,
                       width: inner.width - w, height: inner.height)
    of deRight:
      let w = min(d.size, inner.width)
      rects[i] = CellRect(col: inner.col + inner.width - w,
                          row: inner.row, width: w, height: inner.height)
      inner = CellRect(col: inner.col, row: inner.row,
                       width: inner.width - w, height: inner.height)
    of deTop:
      let h = min(d.size, inner.height)
      rects[i] = CellRect(col: inner.col, row: inner.row,
                          width: inner.width, height: h)
      inner = CellRect(col: inner.col, row: inner.row + h,
                       width: inner.width, height: inner.height - h)
    of deBottom:
      let h = min(d.size, inner.height)
      rects[i] = CellRect(col: inner.col,
                          row: inner.row + inner.height - h,
                          width: inner.width, height: h)
      inner = CellRect(col: inner.col, row: inner.row,
                       width: inner.width, height: inner.height - h)
  DockResult(rects: rects, inner: inner)
