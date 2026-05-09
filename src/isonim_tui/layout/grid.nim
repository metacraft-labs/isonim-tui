## Grid layout policy.
##
## Port of Textual's `textual/layouts/grid.py` (376 LOC). Supports the
## subset of CSS-grid most-used in TUI apps:
##
##   * Row / column templates with `auto`, `1fr` / `Nfr`, fixed-cell
##     dimensions, and percentages.
##   * Row / column gaps (independent).
##   * Cell alignment.
##   * Span (a child can occupy multiple grid cells).
##
## Implementation strategy: the grid is realised in two passes.
##
##   Pass 1 — *track resolution*: walk the templates, compute each
##     track's integer cell width/height by:
##       1. Subtract gap*(N-1) from the parent dimension.
##       2. Subtract any fixed-size or auto-size tracks.
##       3. Distribute the remaining cells across `Nfr` tracks using
##          the same rounding-error-distribution rule as
##          `terminal_layout.distributeError`.
##
##   Pass 2 — *child placement*: for every child with a (row, col, span)
##     index, compute its rectangle by summing the resolved track sizes
##     and gaps. Children placed into the same cell stack on the
##     z-axis (handled by the renderer, not the grid).
##
## Important: this module computes the snapped grid *directly* — it
## doesn't go through Yoga, because Yoga 3.0's grid implementation is
## still partial in the FFI we ship. The output is a `seq[CellRect]` in
## the same coordinate space as `TerminalLayout.cellRect`, so a parent
## that uses grid simply hands the resolved rectangles back to the
## compositor (via `applyToEngine` / direct rect lookup).

import std/[strutils, math]

import ./terminal_layout
import ../css/properties

type
  TrackKind* = enum
    tkAuto      ## Sized to content (treated as 1 cell minimum here)
    tkFixed     ## A literal cell count
    tkFr        ## "Nfr" — fractional remaining space
    tkPercent   ## A percentage of the parent

  Track* = object
    ## One row or column in a grid template.
    kind*: TrackKind
    value*: float    ## Raw value: cells (Fixed), fraction (Fr),
                     ## percent 0..100 (Percent), 1.0 (Auto)

  GridTemplate* = object
    ## A list of tracks plus the gap to insert *between* them.
    tracks*: seq[Track]
    gap*: int

  GridChildPlacement* = object
    ## Where a child sits in the grid. (row, col) are 0-indexed; spans
    ## default to 1.
    handle*: int64
    row*: int
    col*: int
    rowSpan*: int
    colSpan*: int

  GridLayout* = object
    ## A grid configuration. Build via `newGrid` + `addChild`.
    columns*: GridTemplate
    rows*: GridTemplate
    children*: seq[GridChildPlacement]

# ----------------------------------------------------------------------------
# Track parsing helpers
# ----------------------------------------------------------------------------

proc parseTrack*(spec: string): Track =
  ## Parse a single track spec. Examples: "auto", "1fr", "30", "50%".
  let s = spec.strip()
  if s.len == 0 or s == "auto":
    return Track(kind: tkAuto, value: 1.0)
  if s.endsWith("fr"):
    let v = parseFloat(s[0 ..< s.len - 2].strip())
    return Track(kind: tkFr, value: v)
  if s.endsWith("%"):
    let v = parseFloat(s[0 ..< s.len - 1].strip())
    return Track(kind: tkPercent, value: v)
  let v = parseFloat(s)
  return Track(kind: tkFixed, value: v)

proc parseTemplate*(spec: string; gap: int = 0): GridTemplate =
  ## Parse a space-separated track template. `gap` is the inter-track
  ## gap in cells.
  result = GridTemplate(tracks: @[], gap: gap)
  for tok in spec.splitWhitespace():
    result.tracks.add(parseTrack(tok))

proc trackTemplate*(tracks: openArray[Track]; gap: int = 0): GridTemplate =
  result = GridTemplate(tracks: @tracks, gap: gap)

# ----------------------------------------------------------------------------
# Grid construction
# ----------------------------------------------------------------------------

proc newGrid*(columns: GridTemplate; rows: GridTemplate): GridLayout =
  GridLayout(columns: columns, rows: rows, children: @[])

proc place*(grid: var GridLayout; handle: int64; col, row: int;
            colSpan: int = 1; rowSpan: int = 1) =
  ## Place a child at `(col, row)` spanning the given number of tracks.
  grid.children.add(GridChildPlacement(
    handle: handle, col: col, row: row,
    colSpan: max(1, colSpan), rowSpan: max(1, rowSpan)))

# ----------------------------------------------------------------------------
# Track resolution
# ----------------------------------------------------------------------------

proc resolveTracks*(tmpl: GridTemplate; available: int): seq[int] =
  ## Resolve every track in `tmpl` to an integer cell count summing to
  ## `available - gap*(N-1)`. Implements the "fixed → percent → auto →
  ## fr" priority and the "last fr absorbs slack" rule.
  result = newSeq[int](tmpl.tracks.len)
  if tmpl.tracks.len == 0:
    return
  let totalGap = tmpl.gap * max(0, tmpl.tracks.len - 1)
  var remaining = max(0, available - totalGap)

  # Pass 1 — fixed and percent tracks consume their share.
  for i, t in tmpl.tracks:
    case t.kind
    of tkFixed:
      result[i] = max(0, int(t.value))
      remaining -= result[i]
    of tkPercent:
      let cells = int(round(t.value / 100.0 * float(available - totalGap)))
      result[i] = max(0, cells)
      remaining -= result[i]
    of tkAuto:
      result[i] = 1   # Provisional; grid policy elevates auto = 1 cell
      remaining -= 1
    of tkFr:
      result[i] = 0   # Filled in pass 2
  remaining = max(0, remaining)

  # Pass 2 — distribute remaining cells across fr tracks.
  var totalFr = 0.0
  for t in tmpl.tracks:
    if t.kind == tkFr: totalFr += t.value
  if totalFr <= 1e-9:
    return

  var rawFloats: seq[float] = @[]
  var frIndices: seq[int] = @[]
  for i, t in tmpl.tracks:
    if t.kind == tkFr:
      rawFloats.add(t.value / totalFr * float(remaining))
      frIndices.add(i)

  # Reuse the floor-with-largest-remainder rule (mirror
  # terminal_layout.distributeError).
  var floors = newSeq[int](rawFloats.len)
  var fracs = newSeq[float](rawFloats.len)
  var floorSum = 0
  for i, raw in rawFloats:
    let f = int(floor(raw + 1e-6))
    floors[i] = max(0, f)
    fracs[i] = raw - float(f)
    floorSum += floors[i]
  var leftover = max(0, remaining - floorSum)
  # Distribute leftover to largest fractional residues; ties broken in
  # favour of the *later* index (matches the "last fr absorbs slack"
  # contract).
  var order: seq[int] = @[]
  for i in 0 ..< rawFloats.len: order.add i
  proc cmp(a, b: int): int =
    if fracs[a] > fracs[b] + 1e-9: -1
    elif fracs[a] < fracs[b] - 1e-9: 1
    else:
      if a > b: -1 else: 1
  for i in 1 ..< order.len:
    var j = i
    while j > 0 and cmp(order[j], order[j - 1]) < 0:
      let tmp = order[j - 1]
      order[j - 1] = order[j]
      order[j] = tmp
      dec j
  var k = 0
  while leftover > 0:
    let idx = order[k mod order.len]
    floors[idx] += 1
    dec leftover
    inc k
  for i, idx in frIndices:
    result[idx] = floors[i]

# ----------------------------------------------------------------------------
# Layout pass — produce a CellRect per child
# ----------------------------------------------------------------------------

proc trackOffset*(sizes: openArray[int]; gap: int; idx: int): int =
  ## Cell offset of track `idx` from the start of the grid. Sums
  ## sizes and gaps for indices `0 ..< idx`.
  var off = 0
  for i in 0 ..< idx:
    off += sizes[i] + gap
  off

proc trackExtent*(sizes: openArray[int]; gap: int;
                  startIdx, span: int): int =
  ## Total cell extent occupied by tracks `[startIdx, startIdx+span)`,
  ## including gaps *between* the spanned tracks (but not at the edges).
  if span <= 0: return 0
  var ext = 0
  for k in 0 ..< span:
    let i = startIdx + k
    if i < 0 or i >= sizes.len:
      continue
    ext += sizes[i]
    if k > 0: ext += gap
  ext

proc resolveLayout*(grid: GridLayout; parentWidth, parentHeight: int):
                  seq[CellRect] =
  ## Compute one `CellRect` per child placement, in the order the
  ## placements were added. Coordinates are *relative to the grid
  ## container's origin* (caller adds the container's snapped col/row).
  let colSizes = resolveTracks(grid.columns, parentWidth)
  let rowSizes = resolveTracks(grid.rows, parentHeight)
  result = newSeq[CellRect](grid.children.len)
  for i, p in grid.children:
    let col = trackOffset(colSizes, grid.columns.gap, p.col)
    let row = trackOffset(rowSizes, grid.rows.gap, p.row)
    let w = trackExtent(colSizes, grid.columns.gap, p.col, p.colSpan)
    let h = trackExtent(rowSizes, grid.rows.gap, p.row, p.rowSpan)
    result[i] = CellRect(col: col, row: row, width: w, height: h)

# ----------------------------------------------------------------------------
# CSS-driven grid metrics (M5 grid-layout pass)
#
# These helpers wrap the lower-level `resolveTracks` / `resolveLayout`
# pipeline with a CSS-friendly surface. They take the typed grid
# properties produced by the cascade (`grid-size`, `grid-rows`,
# `grid-columns`, `grid-gutter`, plus per-child `column-span` /
# `row-span`) and return the placed `CellRect`s — the same data the
# Container widget (`clGrid`) consumes when it renders.
#
# Track-sizing algorithm (subset of CSS-grid):
#   1. Available space = container size minus the inter-track gaps.
#   2. Fixed-size tracks (raw integer cells, percentages) consume their
#      share first.
#   3. `auto` tracks claim the max intrinsic size of any child placed in
#      that track. Without per-child intrinsic measurement we fall back
#      to one cell — the same provisional rule the lower resolver uses.
#   4. The remaining space is distributed across `fr` tracks
#      proportional to their fraction value, with the largest-residue
#      rounding rule from `terminal_layout.distributeError`.
#
# Placement algorithm (auto-flow row):
#   - Children are walked in declaration order.
#   - Each child has a `(colSpan, rowSpan)` from CSS (`column-span` /
#     `row-span`, both defaulting to 1).
#   - The next free cell is found by sweeping row-major; the placement
#     skips cells already occupied by a prior span. If the child does
#     not fit in the remaining columns of the current row, the cursor
#     advances to the next row.
#   - Rows grow on demand when `grid-size` was specified with cols only.
# ----------------------------------------------------------------------------

type
  GridProps* = object
    ## CSS-driven grid configuration.
    size*: GridSize         ## from `grid-size`
    columns*: seq[GridTrack] ## from `grid-columns` (may be empty)
    rows*: seq[GridTrack]    ## from `grid-rows` (may be empty)
    gutter*: GridGutter      ## from `grid-gutter`

  GridChildProps* = object
    ## Per-child grid attributes (from `column-span` / `row-span`).
    colSpan*: int
    rowSpan*: int

  GridPlacement* = object
    ## A child placed in the grid: which (col, row) it occupies and how
    ## many tracks it spans on each axis.
    col*: int
    row*: int
    colSpan*: int
    rowSpan*: int

proc trackFromCss(t: GridTrack): Track {.inline.} =
  case t.kind
  of gtkAuto:    Track(kind: tkAuto, value: 1.0)
  of gtkFixed:   Track(kind: tkFixed, value: t.value)
  of gtkFr:      Track(kind: tkFr, value: t.value)
  of gtkPercent: Track(kind: tkPercent, value: t.value)

proc effectiveColumns*(p: GridProps): seq[Track] =
  ## Build the effective column track list.
  ##
  ## Priority:
  ##   * If `grid-columns` is provided, use it verbatim.
  ##   * Otherwise, infer N `1fr` tracks from `grid-size.cols`.
  if p.columns.len > 0:
    for t in p.columns: result.add(trackFromCss(t))
  else:
    let n = max(1, p.size.cols)
    for _ in 0 ..< n:
      result.add(Track(kind: tkFr, value: 1.0))

proc effectiveRows*(p: GridProps; rowsNeeded: int): seq[Track] =
  ## Build the effective row track list. `rowsNeeded` is the number of
  ## rows actually consumed by placement; if `grid-size.rows == 0`
  ## (unbounded) and `grid-rows` was not provided, we synthesise that
  ## many `1fr` rows so the resolver produces a height for each.
  if p.rows.len > 0:
    for t in p.rows: result.add(trackFromCss(t))
    while result.len < rowsNeeded:
      # If placement consumed more rows than the explicit list, append
      # `auto` rows — the resolver gives `auto` tracks the provisional
      # 1-cell fallback. This matches Textual's "implicit row" rule.
      result.add(Track(kind: tkAuto, value: 1.0))
  else:
    let bounded =
      if p.size.rows > 0: p.size.rows
      else: max(1, rowsNeeded)
    for _ in 0 ..< bounded:
      result.add(Track(kind: tkFr, value: 1.0))

proc placeChildren*(p: GridProps; children: openArray[GridChildProps]):
                   seq[GridPlacement] =
  ## Auto-flow (row-major) placement. Returns one `GridPlacement` per
  ## child, in the same order they appear in `children`. Children that
  ## span more than the available columns are clamped to the available
  ## width.
  let cols =
    if p.columns.len > 0: p.columns.len
    else: max(1, p.size.cols)
  let maxRows =
    if p.size.rows > 0: p.size.rows
    elif p.rows.len > 0: p.rows.len
    else: high(int)

  result = newSeq[GridPlacement](children.len)

  # Occupancy grid. Use a Table-like sparse approach: a seq[seq[bool]]
  # that grows as needed (rows are appended on demand for auto-flow).
  var occ: seq[seq[bool]] = @[]

  proc ensureRow(r: int) =
    while occ.len <= r:
      occ.add(newSeq[bool](cols))

  proc isFree(r, c, rowSpan, colSpan: int): bool =
    if c < 0 or c + colSpan > cols: return false
    for rr in r ..< r + rowSpan:
      if rr >= maxRows: return false
      ensureRow(rr)
      for cc in c ..< c + colSpan:
        if occ[rr][cc]: return false
    return true

  proc occupy(r, c, rowSpan, colSpan: int) =
    for rr in r ..< r + rowSpan:
      ensureRow(rr)
      for cc in c ..< c + colSpan:
        occ[rr][cc] = true

  var cursorRow = 0
  var cursorCol = 0
  for i, child in children:
    let cs = max(1, min(cols, child.colSpan))
    let rs = max(1, child.rowSpan)
    # Search forwards from the cursor for the first free cell that
    # fits the child. We walk row-major; if `maxRows` is exceeded we
    # still place the child (clamped to the last row, which signals
    # overflow to the caller).
    var r = cursorRow
    var c = cursorCol
    while true:
      if c + cs > cols:
        c = 0
        inc r
      if r >= maxRows:
        # Overflow: pin to the last legal row.
        r = max(0, maxRows - 1)
        c = 0
        break
      if isFree(r, c, rs, cs):
        break
      inc c
    occupy(r, c, rs, cs)
    result[i] = GridPlacement(col: c, row: r, colSpan: cs, rowSpan: rs)
    # Advance the cursor past this child.
    cursorRow = r
    cursorCol = c + cs
    if cursorCol >= cols:
      cursorCol = 0
      inc cursorRow

proc rowsConsumed*(placements: openArray[GridPlacement]): int =
  ## Number of rows touched by the given placements. `0` if none.
  for p in placements:
    let bottom = p.row + p.rowSpan
    if bottom > result: result = bottom

proc resolveCssGrid*(p: GridProps; placements: openArray[GridPlacement];
                     parentWidth, parentHeight: int): seq[CellRect] =
  ## Compute one `CellRect` per placement using the CSS-driven track
  ## specs. Coordinates are *relative to the grid container's origin*.
  let colTracks = effectiveColumns(p)
  let rowTracks = effectiveRows(p, rowsConsumed(placements))
  let colTmpl = trackTemplate(colTracks, gap = p.gutter.horizontal)
  let rowTmpl = trackTemplate(rowTracks, gap = p.gutter.vertical)
  let colSizes = resolveTracks(colTmpl, parentWidth)
  let rowSizes = resolveTracks(rowTmpl, parentHeight)
  result = newSeq[CellRect](placements.len)
  for i, pl in placements:
    let col = trackOffset(colSizes, p.gutter.horizontal, pl.col)
    let row = trackOffset(rowSizes, p.gutter.vertical, pl.row)
    let w = trackExtent(colSizes, p.gutter.horizontal, pl.col, pl.colSpan)
    let h = trackExtent(rowSizes, p.gutter.vertical, pl.row, pl.rowSpan)
    result[i] = CellRect(col: col, row: row, width: w, height: h)
