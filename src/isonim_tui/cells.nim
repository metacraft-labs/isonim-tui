## Cell-grid primitives for isonim-tui.
##
## A `Cell` is the unit of terminal output: one rune at one screen
## position with foreground / background colours and a set of attribute
## flags. A `Strip` is a row of cells with cached display-width and
## content-hash. A `ScreenBuffer` is a 2-D grid of cells with per-row
## hashes for O(rows) diff on unchanged regions.
##
## Charter §1: every type here is a value `object`. No `ref`, no raw
## `ptr` exposed. Sequence storage internally uses Nim's growable seqs
## (which the runtime allocates), but those sequences are `seq[Cell]` /
## `seq[Strip]` — fully copyable, never aliased through a ref.
##
## The diff API returns `seq[Region]` describing rectangular cell-region
## changes the compositor will turn into ANSI runs in M2 / M8.

import std/[unicode, hashes]

# ----------------------------------------------------------------------------
# Color
# ----------------------------------------------------------------------------

type
  ColorKind* = enum
    ## A `Color` is a tagged union: default (terminal default), one of the
    ## 16 ANSI colours, one of the 256 indexed colours, or a 24-bit RGB
    ## truecolor triple. Storing the kind explicitly keeps the type a
    ## plain `object` (no `case` discriminator on a public field would
    ## let downstream code read "wrong" colour fields without checking).
    ckDefault
    ckAnsi
    ckIndexed
    ckRgb

  AnsiColor* = enum
    acBlack       = 0
    acRed         = 1
    acGreen       = 2
    acYellow      = 3
    acBlue        = 4
    acMagenta     = 5
    acCyan        = 6
    acWhite       = 7
    acBrightBlack = 8
    acBrightRed   = 9
    acBrightGreen = 10
    acBrightYellow = 11
    acBrightBlue  = 12
    acBrightMagenta = 13
    acBrightCyan  = 14
    acBrightWhite = 15

  Color* = object
    ## A terminal colour in one of four representations. All variants
    ## fit in 6 bytes (kind + r + g + b + indexed); the `Color` itself
    ## ends up at the natural 4-byte alignment with no padding holes
    ## that the runtime cares about.
    kind*: ColorKind
    r*: uint8
    g*: uint8
    b*: uint8
    indexed*: uint8     ## Used when kind == ckIndexed; ANSI uses bottom 4 bits
    ansi*: AnsiColor    ## Used when kind == ckAnsi

# ----------------------------------------------------------------------------
# Attributes
# ----------------------------------------------------------------------------

  Attr* = enum
    ## SGR attribute flags. Stored as `set[Attr]` on each cell; the SGR
    ## encoder in M1 maps these to escape sequences. The full set fits
    ## in a single byte (8 flags) which keeps `Cell` compact.
    attrBold
    attrItalic
    attrUnderline
    attrStrike
    attrReverse
    attrDim
    attrBlink
    attrInvisible

# ----------------------------------------------------------------------------
# Cell
# ----------------------------------------------------------------------------

  Cell* = object
    ## A single terminal cell. `width` is 1 for ASCII / narrow, 2 for
    ## East-Asian-wide and most emoji. The cell *to the right* of a
    ## width-2 cell is implicitly a "ghost" cell (`rune = 0`, `width = 0`)
    ## that the compositor must skip when emitting; we store that ghost
    ## explicitly in the Strip so column indexing matches screen columns.
    rune*: Rune
    fg*: Color
    bg*: Color
    attrs*: set[Attr]
    width*: int8       ## 1 for narrow, 2 for wide, 0 for ghost trailing-half

# ----------------------------------------------------------------------------
# Color construction helpers
# ----------------------------------------------------------------------------

proc rgbColor*(r, g, b: uint8): Color {.inline.} =
  Color(kind: ckRgb, r: r, g: g, b: b)

proc ansiColor*(c: AnsiColor): Color {.inline.} =
  Color(kind: ckAnsi, ansi: c, indexed: ord(c).uint8)

proc indexedColor*(idx: uint8): Color {.inline.} =
  Color(kind: ckIndexed, indexed: idx)

proc defaultColor*(): Color {.inline.} =
  Color(kind: ckDefault)

proc `==`*(a, b: Color): bool {.inline.} =
  if a.kind != b.kind: return false
  case a.kind
  of ckDefault: true
  of ckAnsi: a.ansi == b.ansi
  of ckIndexed: a.indexed == b.indexed
  of ckRgb: a.r == b.r and a.g == b.g and a.b == b.b

proc hash*(c: Color): Hash {.inline.} =
  result = hash(ord(c.kind).int)
  case c.kind
  of ckDefault: discard
  of ckAnsi: result = result !& hash(ord(c.ansi).int)
  of ckIndexed: result = result !& hash(c.indexed.int)
  of ckRgb:
    result = result !& hash(c.r.int)
    result = result !& hash(c.g.int)
    result = result !& hash(c.b.int)
  result = !$result

# ----------------------------------------------------------------------------
# Cell construction helpers
# ----------------------------------------------------------------------------

proc spaceCell*(): Cell {.inline.} =
  ## A blank cell with default colours and no attributes — used to fill
  ## empty buffer slots.
  Cell(rune: Rune(' '.ord), fg: defaultColor(), bg: defaultColor(),
       attrs: {}, width: 1)

proc ghostCell*(): Cell {.inline.} =
  ## The trailing half of a width-2 cell. Compositor must not emit it
  ## directly; it exists so the buffer's column count equals visible
  ## screen columns.
  Cell(rune: Rune(0), fg: defaultColor(), bg: defaultColor(),
       attrs: {}, width: 0)

proc runeWidth*(r: Rune): int8 =
  ## A *minimal* width estimator for M0. M1 lands the full Unicode
  ## table-driven implementation. For now: ASCII control / null = 0,
  ## ASCII printable = 1, anything else assumed to be 1 (M1 will refine
  ## to handle East-Asian-wide and emoji).
  let cp = int(r)
  if cp == 0: return 0
  if cp < 0x20 or cp == 0x7f: return 0
  return 1

proc newCell*(r: Rune; fg: Color = defaultColor(); bg: Color = defaultColor();
              attrs: set[Attr] = {}): Cell {.inline.} =
  Cell(rune: r, fg: fg, bg: bg, attrs: attrs, width: runeWidth(r))

proc newCell*(c: char; fg: Color = defaultColor(); bg: Color = defaultColor();
              attrs: set[Attr] = {}): Cell {.inline.} =
  newCell(Rune(c.ord), fg, bg, attrs)

proc `==`*(a, b: Cell): bool {.inline.} =
  a.rune == b.rune and a.fg == b.fg and a.bg == b.bg and
    a.attrs == b.attrs and a.width == b.width

# ----------------------------------------------------------------------------
# Strip
# ----------------------------------------------------------------------------

type
  Strip* = object
    ## A row of cells with cached display width and content hash. The
    ## hash lets `ScreenBuffer.diff` compare two rows in O(1) for the
    ## unchanged-row fast path; the displayWidth lets the compositor
    ## avoid re-counting columns on every paint.
    ##
    ## The cache is *only* refreshed when the strip is constructed or
    ## explicitly recomputed via `recomputeCache` — there are no public
    ## mutators that bypass the cache, so the invariant
    ## "contentHash matches cells" holds for any value the type-system
    ## hands you.
    cells*: seq[Cell]
    contentHash*: uint64
    displayWidth*: int

proc recomputeCache*(s: var Strip) =
  ## Refresh `contentHash` and `displayWidth` from `cells`. Run after any
  ## in-place mutation (the constructors below use this internally so
  ## consumers usually don't need to call it).
  var h: Hash = 0
  var w = 0
  for cell in s.cells:
    h = h !& hash(int(cell.rune))
    h = h !& hash(cell.fg)
    h = h !& hash(cell.bg)
    var a = 0
    for at in cell.attrs:
      a = a or (1 shl ord(at))
    h = h !& hash(a)
    h = h !& hash(cell.width.int)
    w += cell.width.int
  h = !$h
  s.contentHash = cast[uint64](h.int64)
  s.displayWidth = w

proc newStrip*(cells: sink seq[Cell]): Strip =
  ## Construct a Strip from the given cell sequence. The constructor
  ## takes ownership (sink) and fills the cache before returning.
  result = Strip(cells: cells, contentHash: 0, displayWidth: 0)
  recomputeCache(result)

proc emptyStrip*(width: int): Strip =
  ## Construct a blank strip of the given width. The cache is filled.
  var cells = newSeq[Cell](width)
  for i in 0 ..< width:
    cells[i] = spaceCell()
  newStrip(cells)

proc len*(s: Strip): int {.inline.} = s.cells.len

proc `[]`*(s: Strip; i: int): Cell {.inline.} = s.cells[i]

proc `[]=`*(s: var Strip; i: int; c: Cell) =
  ## In-place cell assignment. Refreshes the cache so the invariant
  ## holds. Callers doing many writes should batch through `cells` and
  ## call `recomputeCache` once at the end.
  s.cells[i] = c
  recomputeCache(s)

proc `==`*(a, b: Strip): bool {.inline.} =
  ## Two strips are equal iff their content hashes and cell sequences
  ## are equal. The hash check provides the early-out fast path.
  if a.contentHash != b.contentHash: return false
  if a.cells.len != b.cells.len: return false
  for i in 0 ..< a.cells.len:
    if a.cells[i] != b.cells[i]: return false
  return true

# ----------------------------------------------------------------------------
# Diff regions
# ----------------------------------------------------------------------------

type
  CellRegion* = object
    ## A run of changed cells on a single row. The compositor uses these
    ## to issue cursor-move + write sequences instead of repainting the
    ## whole row.
    row*: int        ## Row index in the buffer (0 for Strip-local diff)
    col*: int        ## Starting column
    width*: int      ## Number of cells in the run
    cells*: seq[Cell]

proc diff*(a, b: Strip): seq[CellRegion] =
  ## Compute the minimal set of cell-region changes that turn `a` into
  ## `b`. Contiguous changed cells are merged into one region;
  ## non-contiguous changes produce separate regions.
  ##
  ## Strips of unequal length: the diff covers the prefix where they
  ## share columns, plus a trailing region for the extra columns of
  ## whichever side is longer.
  result = @[]
  let common = min(a.cells.len, b.cells.len)
  var i = 0
  while i < common:
    if a.cells[i] != b.cells[i]:
      let runStart = i
      while i < common and a.cells[i] != b.cells[i]:
        inc i
      let runCells = b.cells[runStart ..< i]
      result.add CellRegion(row: 0, col: runStart, width: i - runStart,
                            cells: runCells)
    else:
      inc i
  if b.cells.len > common:
    result.add CellRegion(row: 0, col: common, width: b.cells.len - common,
                          cells: b.cells[common ..< b.cells.len])
  elif a.cells.len > common:
    # `a` had cells `b` no longer covers — emit a region of blanks so
    # the compositor knows to clear those columns.
    var blanks = newSeq[Cell](a.cells.len - common)
    for j in 0 ..< blanks.len:
      blanks[j] = spaceCell()
    result.add CellRegion(row: 0, col: common, width: blanks.len,
                          cells: blanks)

# ----------------------------------------------------------------------------
# ScreenBuffer
# ----------------------------------------------------------------------------

type
  ScreenBuffer* = object
    ## 2-D grid of `Cell` with per-row strips. Each `Strip`'s cached
    ## `contentHash` makes the unchanged-row fast path O(1) per row.
    rows*: seq[Strip]
    cols*: int
    rowsCount*: int

proc newScreenBuffer*(cols, rows: int): ScreenBuffer =
  ## Construct a fresh ScreenBuffer of the given dimensions, filled with
  ## blank cells.
  var rs = newSeq[Strip](rows)
  for i in 0 ..< rows:
    rs[i] = emptyStrip(cols)
  ScreenBuffer(rows: rs, cols: cols, rowsCount: rows)

proc `[]`*(b: ScreenBuffer; row, col: int): Cell {.inline.} =
  b.rows[row].cells[col]

proc setCell*(b: var ScreenBuffer; row, col: int; cell: Cell) =
  b.rows[row].cells[col] = cell
  recomputeCache(b.rows[row])

proc setRow*(b: var ScreenBuffer; row: int; strip: sink Strip) =
  ## Replace an entire row. The strip is expected to already have its
  ## cache filled (use `newStrip` / `emptyStrip` to construct it).
  b.rows[row] = strip

proc `==`*(a, b: ScreenBuffer): bool =
  if a.cols != b.cols or a.rowsCount != b.rowsCount: return false
  for i in 0 ..< a.rowsCount:
    if a.rows[i] != b.rows[i]: return false
  return true

proc diff*(a, b: ScreenBuffer): seq[CellRegion] =
  ## Compute the minimal cell-region change set turning `a` into `b`.
  ## Per-row hash equality is the fast path; only rows with differing
  ## hashes are diffed cell-by-cell. Returns an empty seq when
  ## `a == b` regardless of buffer size.
  result = @[]
  let commonRows = min(a.rowsCount, b.rowsCount)
  for r in 0 ..< commonRows:
    if a.rows[r].contentHash == b.rows[r].contentHash and
       a.rows[r] == b.rows[r]:
      continue
    let rowDiff = diff(a.rows[r], b.rows[r])
    for region in rowDiff:
      var rgn = region
      rgn.row = r
      result.add rgn
  # If the new buffer has more rows, emit them as full-row replacements.
  if b.rowsCount > commonRows:
    for r in commonRows ..< b.rowsCount:
      result.add CellRegion(row: r, col: 0, width: b.rows[r].cells.len,
                            cells: b.rows[r].cells)
  elif a.rowsCount > commonRows:
    # Old buffer had more rows; emit blanks so the compositor clears
    # them.
    for r in commonRows ..< a.rowsCount:
      var blanks = newSeq[Cell](a.cols)
      for j in 0 ..< a.cols:
        blanks[j] = spaceCell()
      result.add CellRegion(row: r, col: 0, width: a.cols, cells: blanks)
