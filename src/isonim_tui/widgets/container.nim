## widgets/container.nim — Tier-1a `Container` widget.
##
## Port of the `Container` behaviour from `textual/widget.py`. A
## `Container` is the parent of arbitrary child widgets. It supports
## an optional border, an optional viewport-bounded scroll region, and
## (later, in M14) layout-mode switching between vertical / horizontal
## / grid.
##
## *Border + scrolling*: same machinery as `Static`, factored through
## the `borders` module. The container's children are arbitrary
## widget nodes (or raw `TerminalNode`s); the widget builds a
## bordered "frame" around the user content by inserting top / bottom
## border rows and prefix-/suffix-stamping the per-child rows with the
## vertical-edge glyph.
##
## Charter §1: value types in the public API (the children list is
## `seq[TerminalNode]` so adding/removing is a value-copy update); the
## widget itself is a `ref` so callers can mutate its state.

import std/[strutils, tables]
import ../renderer
import ../events
import ../css/properties
import ../layout/grid
import ../layout/terminal_layout
import ./borders

type
  ContainerLayout* = enum
    clVertical
    clHorizontal
    clGrid

  ContainerWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    childWidgets*: seq[TerminalNode]   ## User content rows.
    childSpans*: seq[GridChildProps]   ## Per-child grid spans (parallel
                                       ## to `childWidgets`). Each entry
                                       ## defaults to (1, 1).
    border*: BorderStyle
    borderColor*: string
    layout*: ContainerLayout
    width*: int                        ## Inner width in cells.
    viewportHeight*: int               ## How many rows the viewport
                                       ## shows. Total content can
                                       ## exceed this; the rest is
                                       ## reachable by scrolling.
    scrollY*: int
    scrollable*: bool
    gridProps*: GridProps              ## Grid configuration, valid when
                                       ## `layout == clGrid`. Default
                                       ## `(cols=1, rows=0)` with a
                                       ## single 1fr column.
    gridPlacements*: seq[GridPlacement]  ## Last-computed placement.
    gridRects*: seq[CellRect]            ## Last-computed cell rects.

# Forward declarations so the keydown closure installed in
# `newContainer` can reference `pageDown` / `pageUp` ahead of their
# definitions further down. Closures resolve identifiers lazily so
# only the type needs to be in scope at the closure-construction
# call-site.
proc pageDown*(c: ContainerWidget)
proc pageUp*(c: ContainerWidget)
proc renderTree*(c: ContainerWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitTextRow(r: TerminalRenderer; parent: TerminalNode;
                 text: string; color: string) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc childText(child: TerminalNode): string =
  ## Extract the visible text of `child`. Falls back to `textContent`
  ## (concatenation across sub-text nodes) so any widget that emits
  ## one text payload per child contributes its content. This keeps
  ## the M11 viewport renderer simple — every Tier-1a child whose own
  ## tree boils down to one logical row works without further
  ## annotation.
  textContent(child)

proc childRows(child: TerminalNode): seq[string] =
  ## Extract the per-row text of `child`. Tier-1 widgets in this repo
  ## emit one row of cells per direct child (a wrapper `<div>` whose
  ## subtree contains a single text node). When that's the case we
  ## return one entry per row, preserving the visual stack. Otherwise
  ## we fall back to a single-row payload via `textContent`.
  result = @[]
  if child == nil: return
  if child.children.len > 0:
    var rows: seq[string] = @[]
    for sub in child.children:
      if sub.kind == tnkText:
        # A leaf text node directly under the widget root — one row.
        rows.add sub.text
      else:
        # A wrapper box / button — its subtree concatenates to one row.
        rows.add textContent(sub)
    if rows.len > 0:
      return rows
  # Fall back: single row from the concatenated content.
  return @[textContent(child)]

proc renderVertical(c: ContainerWidget) =
  let r = c.renderer
  let glyphs = bordersGlyphs(c.border)
  let useBorder = c.border != bsNone
  if useBorder:
    emitTextRow(r, c.node, topBorderRow(glyphs, c.width), c.borderColor)
  let visible = max(0, min(c.childWidgets.len - c.scrollY, c.viewportHeight))
  for i in 0 ..< visible:
    let child = c.childWidgets[c.scrollY + i]
    let body = padOrTruncate(childText(child), c.width)
    if useBorder:
      emitTextRow(r, c.node,
                  glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")
  # Pad to viewport.
  for _ in visible ..< c.viewportHeight:
    let body = spaces(c.width)
    if useBorder:
      emitTextRow(r, c.node, glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")
  if useBorder:
    emitTextRow(r, c.node, bottomBorderRow(glyphs, c.width), c.borderColor)

proc renderHorizontal(c: ContainerWidget) =
  ## Real horizontal stack — children are placed left-to-right within
  ## the inner width. Each child gets its own segment, sized either to
  ## its declared cell-width (via `data-cell-width` attribute) or, if
  ## absent, the natural display width of the *first* row of its text
  ## payload (so multi-row widgets like `Button` and `Static` with a
  ## border don't bleed past their own slot). Any remaining cells go
  ## to children that didn't declare a width.
  ##
  ## Per-viewport-row painting walks each child's row sequence (one
  ## entry per direct sub-node, mirroring how widgets emit one
  ## wrapper per visual row) and projects row N of each child into
  ## row N of the container — padded with spaces past the child's
  ## intrinsic height. This fixes the long-standing M11/M23 gap where
  ## `clHorizontal` silently fell through to the vertical render path.
  let r = c.renderer
  let glyphs = bordersGlyphs(c.border)
  let useBorder = c.border != bsNone
  let n = c.childWidgets.len

  # Pre-extract each child's per-row text. We use the row count to
  # paint, and the maximum row 0 / row N width as the natural width.
  var rowsOf = newSeq[seq[string]](n)
  for i, child in c.childWidgets:
    rowsOf[i] = childRows(child)

  # Distribute width across children. If a child carries a
  # `data-cell-width` attribute (set by widgets like Static / Label),
  # honour it; otherwise pick the maximum cell-width across the
  # child's rows. That keeps multi-row widgets (e.g. bordered
  # buttons) from over-committing the slot width to a tall stack.
  var widths = newSeq[int](n)
  if n > 0:
    var declared = newSeq[int](n)
    var declaredTotal = 0
    var elastic = 0
    for i, child in c.childWidgets:
      let attr =
        if child != nil and child.attributes.hasKey("data-cell-width"):
          child.attributes["data-cell-width"]
        else: ""
      if attr.len > 0:
        try:
          let w = parseInt(attr)
          if w > 0:
            declared[i] = w
            declaredTotal += w
            continue
        except ValueError:
          discard
      # Fall back: max cell-width across rows.
      var nat = 0
      for r2 in rowsOf[i]:
        let cw = cellWidth(r2)
        if cw > nat: nat = cw
      if nat > 0:
        declared[i] = nat
        declaredTotal += nat
      else:
        declared[i] = 0
        inc elastic
    let slack = max(0, c.width - declaredTotal)
    if elastic > 0:
      let share = max(1, slack div elastic)
      for i in 0 ..< n:
        if declared[i] == 0:
          widths[i] = share
        else:
          widths[i] = declared[i]
    else:
      for i in 0 ..< n:
        widths[i] = declared[i]
    # If the per-child sum exceeds the inner width, scale each slot
    # down proportionally (preserving order) so the row never spills
    # past the container border. Otherwise hand any leftover slack to
    # the last child so the row sums exactly.
    var used = 0
    for w in widths: used += w
    if used > c.width and used > 0:
      var scaled = newSeq[int](n)
      var sum2 = 0
      for i in 0 ..< n:
        scaled[i] = (widths[i] * c.width) div used
        sum2 += scaled[i]
      if n > 0 and sum2 < c.width:
        scaled[^1] += (c.width - sum2)
      widths = scaled
    elif used < c.width and n > 0 and elastic == 0:
      widths[^1] += (c.width - used)

  if useBorder:
    emitTextRow(r, c.node, topBorderRow(glyphs, c.width), c.borderColor)
  for row in 0 ..< c.viewportHeight:
    var body = ""
    for i in 0 ..< n:
      let raw =
        if row < rowsOf[i].len: rowsOf[i][row]
        else: ""
      body.add(padOrTruncate(raw, widths[i]))
    # Final safety pad / truncate to the inner width.
    if cellWidth(body) < c.width:
      body.add(spaces(c.width - cellWidth(body)))
    elif cellWidth(body) > c.width:
      body = padOrTruncate(body, c.width)
    if useBorder:
      emitTextRow(r, c.node,
                  glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")
  if useBorder:
    emitTextRow(r, c.node, bottomBorderRow(glyphs, c.width), c.borderColor)

proc computeGridLayout*(c: ContainerWidget) =
  ## Re-run the grid resolver for the current children + grid props.
  ## Stores the placement and resolved cell rects on the widget so
  ## downstream consumers (renderer, layout queries) see consistent
  ## metrics.
  c.childSpans.setLen(c.childWidgets.len)
  for i in 0 ..< c.childWidgets.len:
    if c.childSpans[i].colSpan == 0: c.childSpans[i].colSpan = 1
    if c.childSpans[i].rowSpan == 0: c.childSpans[i].rowSpan = 1
  c.gridPlacements = placeChildren(c.gridProps, c.childSpans)
  c.gridRects = resolveCssGrid(c.gridProps, c.gridPlacements,
                               c.width, c.viewportHeight)

proc renderGrid(c: ContainerWidget) =
  ## Render a `clGrid` container. Uses `computeGridLayout` to position
  ## each child in cell coordinates, then paints each row by walking
  ## the placements and emitting the text payload of any child that
  ## contains the current row.
  let r = c.renderer
  let glyphs = bordersGlyphs(c.border)
  let useBorder = c.border != bsNone
  computeGridLayout(c)

  if useBorder:
    emitTextRow(r, c.node, topBorderRow(glyphs, c.width), c.borderColor)

  # Build a 2D buffer of spaces, then stamp each child's text into it
  # at its placed column. We render only viewportHeight rows; if grid
  # output exceeds it, the rest is clipped (matches Textual's clip
  # rule for a grid in a fixed-height container).
  var rowsBuf = newSeq[string](c.viewportHeight)
  for r2 in 0 ..< c.viewportHeight:
    rowsBuf[r2] = spaces(c.width)

  for i, rect in c.gridRects:
    if i >= c.childWidgets.len: continue
    let child = c.childWidgets[i]
    if rect.row < 0 or rect.row >= c.viewportHeight: continue
    let raw = childText(child)
    let payload = padOrTruncate(raw, max(0, rect.width))
    # Splice payload into rowsBuf[rect.row] starting at column rect.col.
    let line = rowsBuf[rect.row]
    let startCol = max(0, rect.col)
    let endCol = min(c.width, startCol + cellWidth(payload))
    if endCol <= startCol:
      continue
    var newLine = line[0 ..< startCol]
    newLine.add(payload)
    if endCol < c.width:
      newLine.add(line[endCol ..< line.len])
    # Truncate if we accidentally over-ran.
    if cellWidth(newLine) > c.width:
      newLine = padOrTruncate(newLine, c.width)
    rowsBuf[rect.row] = newLine

  for r2 in 0 ..< c.viewportHeight:
    let body =
      if cellWidth(rowsBuf[r2]) < c.width:
        rowsBuf[r2] & spaces(c.width - cellWidth(rowsBuf[r2]))
      else:
        rowsBuf[r2]
    if useBorder:
      emitTextRow(r, c.node,
                  glyphs.left & body & glyphs.right, c.borderColor)
    else:
      emitTextRow(r, c.node, body, "")

  if useBorder:
    emitTextRow(r, c.node, bottomBorderRow(glyphs, c.width), c.borderColor)

proc renderTree*(c: ContainerWidget) =
  clearTreeChildren(c.renderer, c.node)
  case c.layout
  of clVertical:
    renderVertical(c)
  of clHorizontal:
    # M23 Batch-3: `clHorizontal` now dispatches to the real
    # left-to-right stacking path landed by the M5-grid pass. The
    # earlier vertical fall-through has been retired; the M23 batch-1
    # / batch-2 goldens that exercised horizontal containers were
    # re-recorded against the new layout in the same change-set.
    renderHorizontal(c)
  of clGrid:
    renderGrid(c)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newContainer*(renderer: TerminalRenderer;
                   width, viewportHeight: int;
                   border: BorderStyle = bsNone;
                   borderColor: string = "";
                   layout: ContainerLayout = clVertical;
                   scrollable: bool = false): ContainerWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "container")
  if scrollable:
    renderer.setAttribute(node, "data-scrollable", "true")
  let c = ContainerWidget(
    renderer: renderer, node: node,
    childWidgets: @[],
    childSpans: @[],
    border: border, borderColor: borderColor,
    layout: layout, width: width,
    viewportHeight: viewportHeight,
    scrollY: 0, scrollable: scrollable,
    gridProps: GridProps(
      size: GridSize(cols: 1, rows: 0),
      columns: @[], rows: @[],
      gutter: GridGutter(horizontal: 0, vertical: 0)),
    gridPlacements: @[],
    gridRects: @[])
  c.renderTree()
  if scrollable:
    renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
      if ev.kind != ekKey: return
      case ev.key.key
      of "pagedown", "pageDown", "PageDown": c.pageDown()
      of "pageup", "pageUp", "PageUp": c.pageUp()
      else: discard)
  c

proc append*(c: ContainerWidget; child: TerminalNode) =
  ## Add a child widget node. Triggers a re-render.
  c.childWidgets.add child
  c.childSpans.add GridChildProps(colSpan: 1, rowSpan: 1)
  c.renderTree()

proc appendAll*(c: ContainerWidget; children: openArray[TerminalNode]) =
  ## Bulk add — only one re-render at the end.
  for child in children:
    c.childWidgets.add child
    c.childSpans.add GridChildProps(colSpan: 1, rowSpan: 1)
  c.renderTree()

# ----------------------------------------------------------------------------
# Scrolling
# ----------------------------------------------------------------------------

proc pageDown*(c: ContainerWidget) =
  if not c.scrollable: return
  let step = max(1, c.viewportHeight - 1)
  let maxOffset = max(0, c.childWidgets.len - c.viewportHeight)
  c.scrollY = min(c.scrollY + step, maxOffset)
  c.renderTree()

proc pageUp*(c: ContainerWidget) =
  if not c.scrollable: return
  let step = max(1, c.viewportHeight - 1)
  c.scrollY = max(0, c.scrollY - step)
  c.renderTree()

proc scrollTo*(c: ContainerWidget; line: int) =
  let maxOffset = max(0, c.childWidgets.len - c.viewportHeight)
  c.scrollY = max(0, min(line, maxOffset))
  c.renderTree()

proc id*(c: ContainerWidget): int {.inline.} = c.node.id

proc setLayout*(c: ContainerWidget; layout: ContainerLayout) =
  ## Switch the container's layout mode. After the M5-grid pass landed,
  ## both horizontal and grid actually render — `clHorizontal` lays
  ## children left-to-right and `clGrid` runs the CSS-driven grid
  ## resolver. The render path picks the right one in `renderTree`.
  c.layout = layout
  case layout
  of clVertical: c.renderer.setStyle(c.node, "layout", "vertical")
  of clHorizontal: c.renderer.setStyle(c.node, "layout", "horizontal")
  of clGrid: c.renderer.setStyle(c.node, "layout", "grid")
  c.renderTree()

proc setGridProps*(c: ContainerWidget; props: GridProps) =
  ## Update the container's grid configuration. Call this after
  ## switching to `clGrid` and providing the cascade-resolved
  ## `grid-size` / `grid-rows` / `grid-columns` / `grid-gutter`. The
  ## widget re-renders.
  c.gridProps = props
  c.renderTree()

proc setChildSpan*(c: ContainerWidget; index: int;
                   colSpan: int = 1; rowSpan: int = 1) =
  ## Set the per-child grid spans (used by `clGrid`). Index is the
  ## position in `childWidgets`; defaults are 1x1.
  c.childSpans.setLen(c.childWidgets.len)
  if index < 0 or index >= c.childSpans.len: return
  c.childSpans[index] = GridChildProps(
    colSpan: max(1, colSpan), rowSpan: max(1, rowSpan))
  if c.layout == clGrid:
    c.renderTree()
