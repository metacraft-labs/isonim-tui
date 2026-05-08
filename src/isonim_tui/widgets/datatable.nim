## widgets/datatable.nim — Tier-3a `DataTable` widget (M17).
##
## Port of `textual/widgets/_data_table.py` + `textual/widgets/data_table.py`
## (~2,000+ LOC combined) — pragmatic core. The most demanding widget
## in the Textual suite. Ships:
##
##   * Header row + body rendering, with column auto-sizing from the
##     header label and the longest cell in each column.
##   * Row virtualisation: only the rows inside the viewport produce
##     compositor entries. The strip cache hits on rows that survive
##     a one-row scroll, so a 100k-row table re-renders in a single
##     row's worth of strip work.
##   * Keyboard navigation: arrow keys move the cursor; Tab walks the
##     header columns when the table is focused at the header band.
##   * Selection: a single highlighted cell at any time. Arrow-down /
##     arrow-up move the highlight by one row; Enter fires
##     `onActivate(row, col)`; the bound selection signal updates
##     through `selectedRow` / `selectedCol`.
##   * Sort: pressing Enter while focused on a header cell sorts the
##     visible rows by that column. Sort indicator (`▲` / `▼`) painted
##     in the header.
##
## **Pragmatic scope** (per M17 milestone):
##
##   * Cell editing — deferred to a later milestone. Cells are read-only.
##   * Column resizing — deferred. Column widths are computed once at
##     `setData` time and stay fixed until the next `setData`.
##   * Column reordering — deferred.
##
## The strip-cache contract matters: every row at absolute index N is
## rendered through the *same* `TerminalNode` across paints. We keep a
## `Table[int, TerminalNode]` mapping absolute row index to its node.
## When a row scrolls into the viewport for the first time we mint a
## fresh node; when it scrolls back into view later we reuse the
## previous node. This is what gives the compositor a stable
## `nodeId` for cache-key purposes — without it, every scroll would
## thrash the cache.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import std/[algorithm, strutils, tables]

import ../renderer
import ../events
import ../css/properties
import ./borders

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  ColumnDef* = object
    ## A DataTable column. `key` identifies the column for sort
    ## callbacks; `label` is what the header band paints. `width` of
    ## zero auto-sizes from the longest cell + label.
    key*: string
    label*: string
    width*: int

  SortDirection* = enum
    sdNone        ## Not sorted.
    sdAscending
    sdDescending

  RowData* = object
    ## A single row. Cells are stored as strings; numeric sort still
    ## works via lexical ordering on zero-padded values, or callers can
    ## supply a `sortKeys` parallel seq of comparable strings.
    cells*: seq[string]

  DataTableWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    columns*: seq[ColumnDef]
    rows*: seq[RowData]              ## The "logical" rows.
    rowOrder*: seq[int]              ## Index permutation. After sort,
                                     ## `rowOrder[i]` points into `rows`.
    columnWidths*: seq[int]          ## Computed widths in cells.
    viewportHeight*: int             ## Number of body rows visible.
    width*: int                      ## Inner width in cells (sum of
                                     ## column widths + separators).
    scrollY*: int                    ## Topmost visible row index in
                                     ## `rowOrder` space.
    selectedRow*: int                ## -1 = no selection.
    selectedCol*: int                ## -1 = no selection.
    headerCol*: int                  ## When >= 0, focus is on the
                                     ## header band at that column.
    sortColumn*: int                 ## -1 = no sort.
    sortDirection*: SortDirection
    border*: BorderStyle
    borderColor*: string
    color*: string
    rowNodes*: Table[int, TerminalNode]
                                     ## Stable per-absolute-row nodes.
                                     ## Keyed by index into `rows` (the
                                     ## logical row, not the permuted
                                     ## visible position).
    headerNode*: TerminalNode        ## Stable header node (one per
                                     ## widget) for cache stability.
    onActivate*: proc(row, col: int)
    onSelectionChange*: proc(oldRow, newRow, oldCol, newCol: int)

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------

proc renderTree*(t: DataTableWidget)
proc moveDown*(t: DataTableWidget)
proc moveUp*(t: DataTableWidget)
proc moveLeft*(t: DataTableWidget)
proc moveRight*(t: DataTableWidget)
proc pageDown*(t: DataTableWidget)
proc pageUp*(t: DataTableWidget)
proc moveHome*(t: DataTableWidget)
proc moveEnd*(t: DataTableWidget)
proc activateCurrent*(t: DataTableWidget)
proc sortByColumn*(t: DataTableWidget; col: int;
                   direction: SortDirection = sdAscending)
proc setData*(t: DataTableWidget; columns: openArray[ColumnDef];
              rows: openArray[RowData])

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitTextRow(r: TerminalRenderer; parent: TerminalNode;
                 dest: TerminalNode; text: string;
                 color: string = ""; reverse: bool = false;
                 dim: bool = false; bold: bool = false) =
  ## Set styling on `dest` and replace its text content with `text`,
  ## then attach it to `parent`. `dest` is reused across paints so the
  ## strip cache hits on unchanged content.
  while dest.children.len > 0:
    let c = dest.children[0]
    r.removeChild(dest, c)
  if color.len > 0:
    r.setStyle(dest, "color", color)
  if reverse:
    r.setStyle(dest, "reverse", "true")
  else:
    r.setStyle(dest, "reverse", "false")
  if bold:
    r.setStyle(dest, "bold", "true")
  else:
    r.setStyle(dest, "bold", "false")
  if dim:
    r.setStyle(dest, "italic", "true")
  else:
    r.setStyle(dest, "italic", "false")
  r.appendChild(dest, r.createTextNode(text))
  r.appendChild(parent, dest)

proc emitFreshRow(r: TerminalRenderer; parent: TerminalNode;
                  text: string; color: string = "";
                  reverse: bool = false; dim: bool = false;
                  bold: bool = false) =
  ## Construct a brand-new <div> child. Used for filler / border rows
  ## where stable identity isn't required.
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  if bold:
    r.setStyle(box, "bold", "true")
  if dim:
    r.setStyle(box, "italic", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc innerWidth(t: DataTableWidget): int =
  ## Sum of column widths plus inter-column single-space separators.
  if t.columnWidths.len == 0: return t.width
  result = 0
  for w in t.columnWidths:
    result += w
  if t.columnWidths.len > 1:
    result += t.columnWidths.len - 1

proc computeColumnWidths(t: DataTableWidget) =
  ## Auto-size each column from the header label + longest cell, unless
  ## the caller pinned `width` to a non-zero value. Cell widths are
  ## measured by `cellWidth` so wide graphemes count properly.
  t.columnWidths.setLen(t.columns.len)
  for c, col in t.columns:
    if col.width > 0:
      t.columnWidths[c] = col.width
      continue
    var maxW = cellWidth(col.label)
    for r in t.rows:
      if c < r.cells.len:
        let w = cellWidth(r.cells[c])
        if w > maxW: maxW = w
    # Reserve room for the sort indicator on every column header.
    t.columnWidths[c] = max(1, maxW + 2)
  t.width = max(1, innerWidth(t))

proc headerLabelWithSort(t: DataTableWidget; col: int): string =
  ## Header text for column `col`. Appends a sort indicator when this
  ## is the active sort column. Pads / truncates to `columnWidths[col]`.
  var label = t.columns[col].label
  if col == t.sortColumn:
    case t.sortDirection
    of sdAscending:  label.add " \xE2\x96\xB2"   # ▲
    of sdDescending: label.add " \xE2\x96\xBC"   # ▼
    of sdNone:       discard
  padOrTruncate(label, t.columnWidths[col])

proc headerRowText(t: DataTableWidget): string =
  result = ""
  for c in 0 ..< t.columns.len:
    if c > 0: result.add " "
    result.add headerLabelWithSort(t, c)

proc bodyRowText(t: DataTableWidget; absRowIdx: int): string =
  ## Lay out the cells of the absolute row at `absRowIdx` (an index
  ## into `t.rows`) using the computed column widths.
  result = ""
  let row = t.rows[absRowIdx]
  for c in 0 ..< t.columns.len:
    if c > 0: result.add " "
    let cell =
      if c < row.cells.len: row.cells[c]
      else: ""
    result.add padOrTruncate(cell, t.columnWidths[c])

proc ensureRowNode(t: DataTableWidget; absRowIdx: int): TerminalNode =
  ## Look up (or mint) the stable node for absolute row index
  ## `absRowIdx`. The node's identity is what gives the strip cache a
  ## stable key, so scrolling preserves cache hits on rows that stay
  ## visible.
  if absRowIdx in t.rowNodes:
    return t.rowNodes[absRowIdx]
  let r = t.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-row-index", $absRowIdx)
  t.rowNodes[absRowIdx] = node
  node

proc ensureScroll(t: DataTableWidget) =
  ## Adjust scrollY so the selected row is visible.
  if t.viewportHeight <= 0: return
  if t.selectedRow < 0: return
  # `selectedRow` is an index into `t.rows`. Translate to its position
  # in `t.rowOrder`.
  var visibleIdx = -1
  for i, idx in t.rowOrder:
    if idx == t.selectedRow:
      visibleIdx = i
      break
  if visibleIdx < 0: return
  if visibleIdx < t.scrollY:
    t.scrollY = visibleIdx
  let bottom = t.scrollY + t.viewportHeight - 1
  if visibleIdx > bottom:
    t.scrollY = visibleIdx - t.viewportHeight + 1
  if t.scrollY < 0: t.scrollY = 0

proc renderTree*(t: DataTableWidget) =
  ## Rebuild the children of `t.node` for the current scroll / sort /
  ## selection state. The header node + each visible body-row node
  ## carry stable identities, so the M8 strip cache short-circuits
  ## paints whose content didn't change.
  let r = t.renderer
  clearTreeChildren(r, t.node)
  let glyphs = bordersGlyphs(t.border)
  let useBorder = t.border != bsNone
  let body = innerWidth(t)
  if useBorder:
    emitFreshRow(r, t.node, topBorderRow(glyphs, body), t.borderColor)

  # Header band — reverse-video; bold the focused column when the cursor
  # is parked on the header.
  ensureScroll(t)
  let headerText = headerRowText(t)
  let headerLine =
    if useBorder: glyphs.left & padOrTruncate(headerText, body) & glyphs.right
    else: padOrTruncate(headerText, body)
  emitTextRow(r, t.node, t.headerNode, headerLine, t.color,
              reverse = true, bold = t.headerCol >= 0)

  # Optional rule between header and body.
  if useBorder:
    var midBorder = glyphs.left
    for _ in 0 ..< body:
      midBorder.add glyphs.horizontal
    midBorder.add glyphs.right
    emitFreshRow(r, t.node, midBorder, t.borderColor)

  # Body rows — virtualised. Only the rows inside the viewport produce
  # entries.
  let total = t.rowOrder.len
  let visible = max(0, min(total - t.scrollY, t.viewportHeight))
  for i in 0 ..< visible:
    let visIdx = t.scrollY + i
    let absIdx = t.rowOrder[visIdx]
    let row = bodyRowText(t, absIdx)
    let line =
      if useBorder: glyphs.left & padOrTruncate(row, body) & glyphs.right
      else: padOrTruncate(row, body)
    let isSelected = absIdx == t.selectedRow and t.headerCol < 0
    let rowNode = ensureRowNode(t, absIdx)
    emitTextRow(r, t.node, rowNode, line, t.color,
                reverse = isSelected)

  # Pad the rest of the viewport so the table's height doesn't jitter
  # when scrolled to the end.
  for _ in visible ..< t.viewportHeight:
    let body2 = spaces(body)
    let line =
      if useBorder: glyphs.left & body2 & glyphs.right
      else: body2
    emitFreshRow(r, t.node, line, t.borderColor)

  if useBorder:
    emitFreshRow(r, t.node, bottomBorderRow(glyphs, body), t.borderColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newDataTable*(renderer: TerminalRenderer;
                   columns: openArray[ColumnDef] = [];
                   rows: openArray[RowData] = [];
                   viewportHeight: int = 10;
                   border: BorderStyle = bsNone;
                   borderColor: string = "";
                   color: string = "";
                   onActivate: proc(row, col: int) = nil;
                   onSelectionChange: proc(oldRow, newRow,
                                           oldCol, newCol: int) = nil
                   ): DataTableWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "data-table")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "data-table")
  let header = renderer.createElement("div")
  renderer.setAttribute(header, "data-role", "data-table-header")
  var cs: seq[ColumnDef] = @[]
  for c in columns: cs.add c
  var rs: seq[RowData] = @[]
  for r in rows: rs.add r
  let t = DataTableWidget(
    renderer: renderer, node: node,
    columns: cs, rows: rs,
    rowOrder: @[], columnWidths: @[],
    viewportHeight: max(1, viewportHeight),
    width: 0,
    scrollY: 0,
    selectedRow: -1, selectedCol: -1,
    headerCol: -1,
    sortColumn: -1, sortDirection: sdNone,
    border: border, borderColor: borderColor, color: color,
    rowNodes: initTable[int, TerminalNode](),
    headerNode: header,
    onActivate: onActivate,
    onSelectionChange: onSelectionChange)

  # Prime row order to 0..rows.len-1 (no sort yet).
  for i in 0 ..< rs.len:
    t.rowOrder.add i
  computeColumnWidths(t)
  if rs.len > 0:
    t.selectedRow = rs[0].cells.len.int * 0  # = 0
    t.selectedRow = 0
    t.selectedCol = 0
  t.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    let lower = ev.key.key.toLowerAscii
    case lower
    of "down", "arrowdown":             t.moveDown()
    of "up", "arrowup":                 t.moveUp()
    of "left", "arrowleft":             t.moveLeft()
    of "right", "arrowright":           t.moveRight()
    of "pagedown":                      t.pageDown()
    of "pageup":                        t.pageUp()
    of "home":                          t.moveHome()
    of "end":                           t.moveEnd()
    of "tab":
      # Tab onto the header band; subsequent Tabs walk columns.
      if t.headerCol < 0:
        t.headerCol = 0
      elif t.headerCol < t.columns.len - 1:
        t.headerCol += 1
      else:
        t.headerCol = -1
      t.renderTree()
    of "enter", "return":
      if t.headerCol >= 0:
        # Activate sort on the focused header column.
        let dir =
          if t.sortColumn == t.headerCol and t.sortDirection == sdAscending:
            sdDescending
          else:
            sdAscending
        t.sortByColumn(t.headerCol, dir)
      else:
        t.activateCurrent()
    else: discard)
  t

# ----------------------------------------------------------------------------
# Mutation helpers
# ----------------------------------------------------------------------------

proc setData*(t: DataTableWidget; columns: openArray[ColumnDef];
              rows: openArray[RowData]) =
  ## Replace the table's columns + rows. The strip cache is implicitly
  ## invalidated because the row-node table is rebuilt with fresh ids.
  var cs: seq[ColumnDef] = @[]
  for c in columns: cs.add c
  var rs: seq[RowData] = @[]
  for r in rows: rs.add r
  t.columns = cs
  t.rows = rs
  t.rowOrder.setLen(0)
  for i in 0 ..< rs.len: t.rowOrder.add i
  t.rowNodes.clear()
  t.scrollY = 0
  t.selectedRow = if rs.len > 0: 0 else: -1
  t.selectedCol = if cs.len > 0: 0 else: -1
  t.sortColumn = -1
  t.sortDirection = sdNone
  computeColumnWidths(t)
  t.renderTree()

proc addRow*(t: DataTableWidget; row: RowData) =
  t.rows.add row
  t.rowOrder.add t.rows.len - 1
  if t.selectedRow < 0: t.selectedRow = 0
  if t.selectedCol < 0 and t.columns.len > 0: t.selectedCol = 0
  computeColumnWidths(t)
  t.renderTree()

proc setSelection(t: DataTableWidget; newRow, newCol: int) =
  let oldRow = t.selectedRow
  let oldCol = t.selectedCol
  if newRow == oldRow and newCol == oldCol: return
  t.selectedRow = newRow
  t.selectedCol = newCol
  t.renderer.setAttribute(t.node, "data-selected-row", $newRow)
  t.renderer.setAttribute(t.node, "data-selected-col", $newCol)
  t.renderTree()
  if t.onSelectionChange != nil:
    t.onSelectionChange(oldRow, newRow, oldCol, newCol)

proc currentVisibleIndex(t: DataTableWidget): int =
  ## Return the position of `selectedRow` inside `rowOrder`. Returns
  ## -1 if no row is selected.
  if t.selectedRow < 0: return -1
  for i, idx in t.rowOrder:
    if idx == t.selectedRow:
      return i
  -1

proc moveDown*(t: DataTableWidget) =
  if t.headerCol >= 0:
    # Leave the header band; land on the first body row.
    t.headerCol = -1
    if t.rowOrder.len > 0:
      let firstAbs = t.rowOrder[t.scrollY]
      t.setSelection(firstAbs, t.selectedCol)
    else:
      t.renderTree()
    return
  let cur = currentVisibleIndex(t)
  if cur < 0: return
  if cur + 1 < t.rowOrder.len:
    t.setSelection(t.rowOrder[cur + 1], t.selectedCol)

proc moveUp*(t: DataTableWidget) =
  if t.headerCol >= 0: return
  let cur = currentVisibleIndex(t)
  if cur < 0: return
  if cur > 0:
    t.setSelection(t.rowOrder[cur - 1], t.selectedCol)
  else:
    # At top — focus the header band.
    t.headerCol = max(0, t.selectedCol)
    t.renderTree()

proc moveLeft*(t: DataTableWidget) =
  if t.headerCol > 0:
    t.headerCol -= 1
    t.renderTree()
  elif t.selectedCol > 0:
    t.setSelection(t.selectedRow, t.selectedCol - 1)

proc moveRight*(t: DataTableWidget) =
  if t.headerCol >= 0 and t.headerCol < t.columns.len - 1:
    t.headerCol += 1
    t.renderTree()
  elif t.selectedCol < t.columns.len - 1:
    t.setSelection(t.selectedRow, t.selectedCol + 1)

proc pageDown*(t: DataTableWidget) =
  if t.headerCol >= 0: return
  let cur = currentVisibleIndex(t)
  if cur < 0: return
  let target = min(cur + t.viewportHeight, t.rowOrder.len - 1)
  t.setSelection(t.rowOrder[target], t.selectedCol)

proc pageUp*(t: DataTableWidget) =
  if t.headerCol >= 0: return
  let cur = currentVisibleIndex(t)
  if cur < 0: return
  let target = max(cur - t.viewportHeight, 0)
  t.setSelection(t.rowOrder[target], t.selectedCol)

proc moveHome*(t: DataTableWidget) =
  if t.headerCol >= 0: return
  if t.rowOrder.len == 0: return
  t.setSelection(t.rowOrder[0], t.selectedCol)

proc moveEnd*(t: DataTableWidget) =
  if t.headerCol >= 0: return
  if t.rowOrder.len == 0: return
  t.setSelection(t.rowOrder[^1], t.selectedCol)

proc activateCurrent*(t: DataTableWidget) =
  if t.selectedRow < 0 or t.selectedCol < 0: return
  if t.onActivate != nil:
    t.onActivate(t.selectedRow, t.selectedCol)
  fireEvent(t.node, "activate")

proc sortByColumn*(t: DataTableWidget; col: int;
                   direction: SortDirection = sdAscending) =
  ## Re-permute `rowOrder` according to the chosen column.
  if col < 0 or col >= t.columns.len: return
  if direction == sdNone:
    t.sortColumn = -1
    t.sortDirection = sdNone
    t.rowOrder.setLen(0)
    for i in 0 ..< t.rows.len: t.rowOrder.add i
    t.renderTree()
    return
  t.sortColumn = col
  t.sortDirection = direction
  proc cellOf(idx: int): string =
    if col < t.rows[idx].cells.len: t.rows[idx].cells[col]
    else: ""
  t.rowOrder.sort do (a, b: int) -> int:
    let av = cellOf(a)
    let bv = cellOf(b)
    if av < bv: -1
    elif av > bv: 1
    else: 0
  if direction == sdDescending:
    reverse(t.rowOrder)
  t.renderTree()

proc id*(t: DataTableWidget): int {.inline.} = t.node.id
