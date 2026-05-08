## Stream (flow) layout policy.
##
## Port of Textual's `textual/layouts/stream.py`. Children flow
## horizontally; when a child would exceed the parent's width the layout
## wraps to the next row (the height of the row is the max height of the
## children on it). This matches text-like flow / inline-block behaviour.
##
## Each item supplies an integer cell width and integer cell height; the
## layout returns a `CellRect` for each item. Used by widgets that
## render variable-length tag chips, breadcrumbs, etc.

import ./terminal_layout

type
  StreamItem* = object
    handle*: int64
    width*: int
    height*: int

  StreamLayout* = object
    items*: seq[StreamItem]
    hgap*: int    ## Horizontal gap between items on the same row.
    vgap*: int    ## Vertical gap between rows.

proc newStream*(hgap: int = 0; vgap: int = 0): StreamLayout =
  StreamLayout(items: @[], hgap: hgap, vgap: vgap)

proc add*(s: var StreamLayout; handle: int64; width, height: int) =
  s.items.add(StreamItem(handle: handle, width: width, height: height))

proc resolveLayout*(s: StreamLayout; parentWidth: int):
                  tuple[rects: seq[CellRect]; totalHeight: int] =
  ## Compute a `CellRect` per item plus the total height needed.
  ## Wrapping rule: if the cursor + item.width exceeds `parentWidth`
  ## *and* the cursor is already non-zero, wrap to the next row. An
  ## item wider than the parent occupies its own row regardless.
  var rects = newSeq[CellRect](s.items.len)
  var col = 0
  var row = 0
  var rowHeight = 0
  var totalHeight = 0
  for i, it in s.items:
    let needsWrap = col > 0 and (col + it.width > parentWidth)
    if needsWrap:
      row += rowHeight + s.vgap
      col = 0
      rowHeight = 0
    let w =
      if it.width > parentWidth: parentWidth
      else: it.width
    rects[i] = CellRect(col: col, row: row, width: w, height: it.height)
    let advance = w + s.hgap
    col += advance
    if it.height > rowHeight: rowHeight = it.height
    if row + rowHeight > totalHeight: totalHeight = row + rowHeight
  (rects: rects, totalHeight: totalHeight)
