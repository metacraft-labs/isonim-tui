## Compositor — M8 optimised version.
##
## Replaces the M2 full-repaint compositor with one that
##
##   * caches strips per node by `(nodeId, contentHash, styleHash, width)`
##     so unchanged rows skip cell-by-cell construction (port of
##     Textual's `_compositor.Compositor._strip_cache`),
##   * tracks dirty regions by diffing the freshly-rendered buffer
##     against the last paint's buffer and coalescing adjacent runs
##     within a row,
##   * supports layered output via a `layer` style (numeric N, default 0)
##     — nodes are gathered into per-layer entries and composited in
##     ascending order, so modals / popovers / focus rings cleanly
##     overlay the base tree,
##   * emits SGR-aware minimal byte sequences per dirty row: one
##     `cursorTo(row, col)` per region, then runs of cells whose style
##     matches the trailing SGR are emitted as a single SGR + N runes
##     (port of Textual's `_segment_tools.simplify_segments`),
##   * stays idle: if the rendered buffer matches the last paint, no
##     bytes are written to the driver.
##
## Public surface preserved verbatim from M2:
##   * `Compositor`, `newCompositor`, `resize`
##   * `render(c, root)` — produces a `ScreenBuffer`
##   * `paint(c, root, driver)` — diff-driven write to the driver
##   * `layoutRegionFor(c, root, nodeId)`
##   * `nodesInRenderOrder(root)`
##   * Public fields `lastBuffer`, `lastDirty` so introspection /
##     annotated-svg snapshots still resolve.
##
## New public surface added by M8:
##   * `StripCacheStats` (value object) + `stats(c)` accessor
##   * `clearStripCache(c)` for tests
##   * `coalesce(regions)` and `diffRegions(a, b)` for unit testing
##   * `emitRegion(prev, region)` and `emitRow(prev, regions)` for unit
##     testing the byte writer in isolation
##
## *Charter §1.* The compositor is `ref object` (acceptable for
## internal state per the milestone preamble); every value flowing
## through its public API is a value object (`Strip`, `Cell`,
## `ScreenBuffer`, `CellRegion`, `Style`, `StripCacheStats`).

import std/[hashes, strutils, tables, unicode]

import ./cells
import ./renderer
import ./drivers/headless_driver
import ./text/ansi
import ./text/width

# ----------------------------------------------------------------------------
# Layered layout entry
# ----------------------------------------------------------------------------

type
  LayoutEntry = object
    ## Flattened layout produced by the placeholder layout pass. Each
    ## entry is one rectangular slot at a given layer. The tree walk
    ## flattens *visible* nodes into one of these per row of textual
    ## content; nodes carrying a `layer` style produce entries on the
    ## addressed layer (default = 0). The compositor stacks layers in
    ## ascending order, so layer=10 modals sit on top of layer=0 base.
    row: int
    col: int
    width: int
    text: string
    nodeId: int
    layer: int
    fg: Color
    bg: Color
    attrs: set[Attr]
    fillBackground: bool   ## When true, the entry's full rectangle is
                           ## filled with `bg` even if it's wider than
                           ## the rendered text (so modals visually mask
                           ## the layer below). Set when a node has an
                           ## explicit background-color or when it
                           ## carries a `layer` > 0.

  StyleSnapshot = object
    fg: Color
    bg: Color
    attrs: set[Attr]

  StripCacheStats* = object
    ## Snapshot of the strip cache's hit / miss counters since the
    ## compositor was constructed. Tests assert `hits / (hits + misses)`
    ## ≥ 95% under scroll-by-one-row workloads.
    hits*: int
    misses*: int

  StripCacheEntry = object
    ## One slot of the per-node strip cache. The key is the input
    ## hash (`contentHash` of the proposed cells) plus the width;
    ## the value is the constructed `Strip`. When a node mutates,
    ## its entry is invalidated automatically because the input
    ## hash changes.
    inputHash: uint64
    width: int
    strip: Strip

  Compositor* = ref object
    ## Optimised compositor. Owns the per-frame work buffers, the
    ## strip cache, and the snapshot of the previous paint.
    cols*: int
    rows*: int
    lastBuffer*: ScreenBuffer       ## The buffer produced by the last
                                    ## paint. Initial value is a fully
                                    ## blank buffer (matches the screen
                                    ## state a real driver leaves after
                                    ## `start()`).
    lastDirty*: seq[CellRegion]     ## Dirty regions from the last paint
                                    ## (coalesced). Introspection +
                                    ## annotated-svg snapshots consume
                                    ## this list directly.
    initialPainted*: bool           ## False before the first paint —
                                    ## the first paint is unconditional
                                    ## (the driver's initial screen is
                                    ## blank, but we still emit a full
                                    ## paint so the user sees the mount
                                    ## state).
    stripCache: Table[int, StripCacheEntry]
    cacheHits: int
    cacheMisses: int

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newCompositor*(cols, rows: int): Compositor =
  ## Construct a fresh compositor of the given dimensions. The strip
  ## cache starts empty; counters start at zero.
  Compositor(
    cols: cols, rows: rows,
    lastBuffer: newScreenBuffer(cols, rows),
    lastDirty: @[],
    initialPainted: false,
    stripCache: initTable[int, StripCacheEntry](),
    cacheHits: 0,
    cacheMisses: 0)

proc resize*(c: Compositor; cols, rows: int) =
  ## Resize and reset. The strip cache is dropped because all cached
  ## strips were sized for the old `cols`.
  c.cols = cols
  c.rows = rows
  c.lastBuffer = newScreenBuffer(cols, rows)
  c.lastDirty = @[]
  c.initialPainted = false
  c.stripCache.clear()
  c.cacheHits = 0
  c.cacheMisses = 0

# ----------------------------------------------------------------------------
# Strip cache accessors
# ----------------------------------------------------------------------------

proc stats*(c: Compositor): StripCacheStats {.inline.} =
  ## Return a snapshot of the cache's hit / miss counters.
  StripCacheStats(hits: c.cacheHits, misses: c.cacheMisses)

proc clearStripCache*(c: Compositor) =
  ## Drop every cached strip. Used when the theme / stylesheet revision
  ## bumps so strips that captured stale styling are recomputed.
  c.stripCache.clear()
  c.cacheHits = 0
  c.cacheMisses = 0

# ----------------------------------------------------------------------------
# Style extraction (from `node.styles`)
# ----------------------------------------------------------------------------

proc parseColorOrDefault(s: string): Color =
  ## Parse a colour from the inline-style table. Honours the 16
  ## ANSI palette names plus `default`; anything else falls back to
  ## the terminal default. (Full CSS colour parsing lives in
  ## `theme/color.nim`; the compositor only needs ANSI / default for
  ## the M8 test surface — the M5/M6 cascade hands the compositor a
  ## materialised inline value in those styles anyway.)
  if s.len == 0 or s == "default" or s == "transparent":
    return defaultColor()
  return namedColor(s)

proc layerFromStyle(node: TerminalNode; parentLayer: int): int =
  ## Resolve the layer for `node`. Inherits the parent's layer unless
  ## a `layer` style is set on the node itself; `position: overlay`
  ## promotes a node to layer 1 when no explicit layer is given.
  if node == nil: return parentLayer
  if "layer" in node.styles:
    let raw = node.styles["layer"]
    try:
      return parseInt(raw)
    except CatchableError:
      return parentLayer
  if "position" in node.styles and node.styles["position"] == "overlay":
    return max(parentLayer, 1)
  parentLayer

proc styleFor(node: TerminalNode; inherited: StyleSnapshot):
              tuple[snap: StyleSnapshot; hasBg: bool] =
  ## Resolve foreground / background / attrs for `node`. Inherits from
  ## the parent unless overridden. `hasBg` reports whether the node
  ## itself contributed a `background-color` value (used so layered
  ## entries fill the whole rectangle on opaque backgrounds).
  result.snap = inherited
  result.hasBg = false
  if node == nil: return
  if "color" in node.styles:
    result.snap.fg = parseColorOrDefault(node.styles["color"])
  if "background-color" in node.styles:
    let bg = node.styles["background-color"]
    if bg.len > 0 and bg != "default" and bg != "transparent":
      result.snap.bg = parseColorOrDefault(bg)
      result.hasBg = true
  if "background" in node.styles:
    let bg = node.styles["background"]
    if bg.len > 0 and bg != "default" and bg != "transparent":
      result.snap.bg = parseColorOrDefault(bg)
      result.hasBg = true
  if "bold" in node.styles and node.styles["bold"] == "true":
    result.snap.attrs.incl(attrBold)
  if "dim" in node.styles and node.styles["dim"] == "true":
    result.snap.attrs.incl(attrDim)
  if "italic" in node.styles and node.styles["italic"] == "true":
    result.snap.attrs.incl(attrItalic)
  if "underline" in node.styles and node.styles["underline"] == "true":
    result.snap.attrs.incl(attrUnderline)
  if "reverse" in node.styles and node.styles["reverse"] == "true":
    result.snap.attrs.incl(attrReverse)

# ----------------------------------------------------------------------------
# Tree walker — flattens to LayoutEntries with layer + style.
# ----------------------------------------------------------------------------

proc subtreeText(node: TerminalNode): string =
  ## Concatenate every `tnkText` descendant's text in document order.
  ## Used by the inline-row layout to extract a label's display text
  ## from a label container (e.g. ``<span class=settings-label>Dark
  ## mode</span>`` → ``"Dark mode"``).
  if node == nil: return ""
  if node.kind == tnkText:
    return node.text
  for ch in node.children:
    result.add subtreeText(ch)

proc widgetGlyph(node: TerminalNode): string =
  ## Map a trailing widget node to its inline-row glyph representation.
  ## Returns an empty string when the node's kind isn't recognised by
  ## the inline path — the caller then falls back to the recursive
  ## row-per-child walk so unsupported widgets don't regress.
  ##
  ## Recognised inputs:
  ##   * ``tnkInput[type=checkbox]`` → ``[ ]`` / ``[x]`` (per the
  ##     `checked` attribute).
  ##   * ``tnkInput[type=number]`` → ``[- VALUE -]`` (per `value` /
  ##     `data-value`).
  ##   * ``tnkInput[type=text]`` → bare `value` text.
  ##   * ``tnkButton`` with text content → ``[ TEXT ]``.
  ##   * ``tnkBox[data-widget=option-list]`` → ``< SELECTED >`` (per
  ##     the child carrying `data-selected="true"`, or the box's
  ##     `data-value`).
  ##
  ## Settings-app host containers (``class="settings-toggle"`` /
  ## ``settings-number`` / ``settings-choice``) wrap their real widget
  ## tree under a host div carrying ``data-value``. The inline path
  ## recognises those host containers directly using the host's
  ## ``data-value`` attribute, so the glyph rendering doesn't depend
  ## on the host's internal node layout.
  if node == nil: return ""
  let hostClass = node.attributes.getOrDefault("class", "")
  case hostClass
  of "settings-toggle":
    let value = node.attributes.getOrDefault("data-value", "")
    if value == "on": return "[x]"
    return "[ ]"
  of "settings-number":
    let value = node.attributes.getOrDefault("data-value", "")
    let suffix = node.attributes.getOrDefault("data-suffix", "")
    if value.len == 0: return "[-  -]"
    if suffix.len > 0:
      return "[- " & value & suffix & " -]"
    return "[- " & value & " -]"
  of "settings-choice":
    let value = node.attributes.getOrDefault("data-value", "")
    if value.len == 0: return "<  >"
    return "< " & value & " >"
  else:
    discard
  case node.kind
  of tnkInput:
    let kindAttr = node.attributes.getOrDefault("type", "text")
    case kindAttr
    of "checkbox":
      let checked = node.attributes.getOrDefault("checked", "")
      if checked == "true" or checked == "checked" or checked == "on":
        return "[x]"
      return "[ ]"
    of "number":
      var value = node.attributes.getOrDefault("value", "")
      if value.len == 0:
        value = node.attributes.getOrDefault("data-value", "")
      return "[- " & value & " -]"
    of "text":
      let value = node.attributes.getOrDefault("value", "")
      return value
    else:
      return ""
  of tnkButton:
    let label = subtreeText(node)
    if label.len == 0: return ""
    return "[ " & label & " ]"
  of tnkBox:
    let widget = node.attributes.getOrDefault("data-widget", "")
    if widget == "option-list":
      # Cycler form: `< SELECTED >`. The selected option is whichever
      # child carries `data-selected="true"`; the option's display
      # text is its `subtreeText`. Fall back to `data-value` (or empty)
      # if no child is marked.
      for ch in node.children:
        if ch.attributes.getOrDefault("data-selected", "") == "true":
          return "< " & subtreeText(ch) & " >"
      let value = node.attributes.getOrDefault("data-value", "")
      if value.len > 0:
        return "< " & value & " >"
      return ""
    return ""
  else:
    return ""

proc isInlineDescription(node: TerminalNode): bool =
  ## A child counts as the inline-row's description span when it's a
  ## `tnkBox` carrying ``class="settings-description"``. Description
  ## spans don't share the inline label+widget row; the walker emits
  ## them on a separate row below.
  if node == nil or node.kind != tnkBox: return false
  node.attributes.getOrDefault("class", "") == "settings-description"

proc walkLayoutImpl(node: TerminalNode; row: var int; cols: int;
                    parentStyle: StyleSnapshot;
                    parentLayer: int;
                    parentHasBg: bool;
                    entries: var seq[LayoutEntry]) =
  ## Recursive tree walk. Mirrors M2's flatten-to-rows model but
  ## propagates inherited foreground / background / attribute style and
  ## the active layer. Boxes whose children are all text collapse to a
  ## single row; mixed boxes emit one row per child unless they opt in
  ## to inline layout via ``data-tui-row="inline"`` (label spans laid
  ## out left, trailing widget rendered as a glyph on the right of the
  ## same row).
  if node == nil: return
  case node.kind
  of tnkText:
    let resolved = styleFor(node, parentStyle)
    entries.add LayoutEntry(
      row: row, col: 0, width: cols, text: node.text, nodeId: node.id,
      layer: parentLayer,
      fg: resolved.snap.fg, bg: resolved.snap.bg,
      attrs: resolved.snap.attrs,
      fillBackground: parentHasBg or resolved.hasBg or parentLayer > 0)
    inc row
  of tnkBox, tnkButton, tnkInput:
    let resolved = styleFor(node, parentStyle)
    let nodeLayer = layerFromStyle(node, parentLayer)
    let nodeHasBg = parentHasBg or resolved.hasBg or nodeLayer > parentLayer
    var allText = node.children.len > 0
    for ch in node.children:
      if ch.kind != tnkText:
        allText = false
        break
    if allText:
      # Detect per-child style overrides. When any child text node
      # carries its own `color` / `background-color` / `bold` / `dim` /
      # `italic` / `underline` / `reverse` style, we must NOT fuse into
      # a single LayoutEntry — the fused entry only honours the parent's
      # resolved style, which would silently drop the per-segment
      # accent colour. Emit one LayoutEntry per child at adjacent
      # columns instead, anchored at the same row.
      var anyChildStyled = false
      for ch in node.children:
        if ch.styles.len > 0:
          anyChildStyled = true
          break
      if anyChildStyled:
        var segCol = 0
        for ch in node.children:
          if ch.text.len == 0: continue
          let chResolved = styleFor(ch, resolved.snap)
          var w = 0
          for rune in runes(ch.text):
            w.inc(displayWidth(rune))
          let remaining = max(0, cols - segCol)
          let segWidth = min(w, remaining)
          entries.add LayoutEntry(
            row: row, col: segCol,
            width: segWidth,
            text: ch.text, nodeId: ch.id,
            layer: nodeLayer,
            fg: chResolved.snap.fg, bg: chResolved.snap.bg,
            attrs: chResolved.snap.attrs,
            fillBackground: nodeHasBg or chResolved.hasBg)
          segCol.inc(segWidth)
          if segCol >= cols: break
        inc row
      else:
        var s = ""
        for ch in node.children:
          s.add ch.text
        entries.add LayoutEntry(
          row: row, col: 0, width: cols, text: s, nodeId: node.id,
          layer: nodeLayer,
          fg: resolved.snap.fg, bg: resolved.snap.bg,
          attrs: resolved.snap.attrs,
          fillBackground: nodeHasBg)
        inc row
    else:
      if node.children.len == 0 and nodeHasBg:
        entries.add LayoutEntry(
          row: row, col: 0, width: cols, text: "", nodeId: node.id,
          layer: nodeLayer,
          fg: resolved.snap.fg, bg: resolved.snap.bg,
          attrs: resolved.snap.attrs,
          fillBackground: nodeHasBg)
        inc row
        return
      # Inline-row opt-in. When ``data-tui-row="inline"`` is set on a
      # container with mixed-kind children, the walker lays out the
      # label spans on the left of one row and renders the trailing
      # widget node as a glyph on the right of the same row. Any
      # description spans (``class="settings-description"``) render on
      # their own row below, indented two cells so the hierarchy reads
      # at a glance. If the trailing widget isn't recognised by
      # ``widgetGlyph`` (returns ""), the walker falls back to the
      # existing per-child recursion so unsupported widgets don't
      # regress to a broken inline layout.
      if node.attributes.getOrDefault("data-tui-row", "") == "inline" and
         node.children.len >= 2:
        let widgetNode = node.children[^1]
        let glyph = widgetGlyph(widgetNode)
        if glyph.len > 0:
          # Build the label text from every child that's neither the
          # trailing widget nor a description span.
          var labelText = ""
          var descriptions: seq[TerminalNode] = @[]
          for i in 0 ..< node.children.len - 1:
            let ch = node.children[i]
            if isInlineDescription(ch):
              descriptions.add ch
            else:
              labelText.add subtreeText(ch)
          # Anchor the glyph at the right edge of the row. When the
          # label would overflow into the glyph slot we shrink the
          # label's width so the glyph still lands at column
          # (cols - glyph.runeCount).
          let glyphRuneCount = block:
            var n = 0
            for _ in runes(glyph): inc n
            n
          let glyphCol = max(0, cols - glyphRuneCount)
          # Leader-dot fill. When the label leaves enough room (>= 4
          # cells of horizontal gap), pad the label with `" ........ "`
          # so the eye follows a dotted line from the label to its
          # widget. This is the macOS System Preferences / classic
          # `menuconfig` pattern; without it the three widgets read as
          # a vertical stack hugging the right margin and the binding
          # back to each label is visually ambiguous.
          let labelRuneCount = block:
            var n = 0
            for _ in runes(labelText): inc n
            n
          # Available gap = cols - label - widget. We reserve one space
          # on each side of the dotted run, so dots only render when
          # the gap is at least 4 cells (` .. `).
          let gap = glyphCol - labelRuneCount
          var renderedLabel = labelText
          if gap >= 4 and labelText.len > 0:
            let dotCount = gap - 3   # one leading space, one trailing space, one before-widget space
            if dotCount >= 1:
              renderedLabel.add ' '
              for _ in 0 ..< dotCount:
                renderedLabel.add '.'
              renderedLabel.add ' '
          entries.add LayoutEntry(
            row: row, col: 0,
            width: max(0, glyphCol),
            text: renderedLabel, nodeId: node.id,
            layer: nodeLayer,
            fg: resolved.snap.fg, bg: resolved.snap.bg,
            attrs: resolved.snap.attrs,
            fillBackground: nodeHasBg)
          # Widget glyph entry — owned by the widget node so cache
          # invalidation on a widget mutation still fires correctly.
          let widgetStyle = styleFor(widgetNode, resolved.snap)
          entries.add LayoutEntry(
            row: row, col: glyphCol,
            width: glyphRuneCount,
            text: glyph, nodeId: widgetNode.id,
            layer: nodeLayer,
            fg: widgetStyle.snap.fg, bg: widgetStyle.snap.bg,
            attrs: widgetStyle.snap.attrs,
            fillBackground: nodeHasBg or widgetStyle.hasBg)
          inc row
          # Each description span renders on its own row, indented
          # two columns. We synthesise a LayoutEntry directly rather
          # than recursing so the indent is honoured even when the
          # description span's container would otherwise collapse to
          # column 0.
          for desc in descriptions:
            let descStyle = styleFor(desc, resolved.snap)
            let descText = subtreeText(desc)
            entries.add LayoutEntry(
              row: row, col: 2,
              width: max(0, cols - 2),
              text: descText, nodeId: desc.id,
              layer: nodeLayer,
              fg: descStyle.snap.fg, bg: descStyle.snap.bg,
              attrs: descStyle.snap.attrs,
              fillBackground: nodeHasBg or descStyle.hasBg)
            inc row
          return
      for ch in node.children:
        walkLayoutImpl(ch, row, cols, resolved.snap, nodeLayer,
                       nodeHasBg, entries)

proc walkLayoutClean(node: TerminalNode; cols: int): seq[LayoutEntry] =
  ## Convenience wrapper; the recursion uses `var` row + accumulator
  ## so the public surface stays a plain seq.
  result = @[]
  if node == nil: return
  var row = 0
  let parentStyle = StyleSnapshot(
    fg: defaultColor(), bg: defaultColor(), attrs: {})
  walkLayoutImpl(node, row, cols, parentStyle, 0, false, result)

# ----------------------------------------------------------------------------
# Strip construction (cache-aware)
# ----------------------------------------------------------------------------

proc rawCellsForEntry(entry: LayoutEntry; cols: int): seq[Cell] =
  ## Project a layout entry into cells *before* the cache lookup. The
  ## entry's text is laid out at column zero; the trailing background
  ## (if `fillBackground` is set) is painted with the entry's bg.
  result = newSeq[Cell]()
  var col = 0
  let limit = min(entry.col + entry.width, cols)
  while col < entry.col and col < limit:
    result.add spaceCell()
    inc col
  for r in runes(entry.text):
    if col >= limit: break
    let w = displayWidth(r)
    if w == 0:
      continue
    if w >= 2:
      if col + 1 >= limit: break
      result.add Cell(rune: r, fg: entry.fg, bg: entry.bg,
                      attrs: entry.attrs, width: 2)
      result.add ghostCell()
      col += 2
    else:
      result.add Cell(rune: r, fg: entry.fg, bg: entry.bg,
                      attrs: entry.attrs, width: 1)
      col += 1
  while col < limit:
    if entry.fillBackground:
      result.add Cell(rune: Rune(' '.ord), fg: entry.fg, bg: entry.bg,
                      attrs: entry.attrs, width: 1)
    else:
      result.add spaceCell()
    inc col
  while col < cols:
    result.add spaceCell()
    inc col

proc inputHashForEntry(entry: LayoutEntry; cols: int): uint64 =
  ## Hash the *inputs* that determine the entry's cells: text, fg, bg,
  ## attrs, layer, fill flag, and the destination width. Matches in
  ## the cache mean the cells will be byte-identical so we can skip
  ## reconstruction.
  var h: Hash = 0
  h = h !& hash(entry.text)
  h = h !& hash(entry.fg)
  h = h !& hash(entry.bg)
  var a = 0
  for at in entry.attrs:
    a = a or (1 shl ord(at))
  h = h !& hash(a)
  h = h !& hash(entry.layer)
  h = h !& hash(if entry.fillBackground: 1 else: 0)
  h = h !& hash(entry.col)
  h = h !& hash(entry.width)
  h = h !& hash(cols)
  cast[uint64](!$h)

proc stripForEntry(c: Compositor; entry: LayoutEntry): Strip =
  ## Cache-aware strip construction. Returns a cached Strip on hit;
  ## reconstructs and stores on miss.
  let key = entry.nodeId
  let want = inputHashForEntry(entry, c.cols)
  if key in c.stripCache:
    let cached = c.stripCache[key]
    if cached.inputHash == want and cached.width == c.cols:
      inc c.cacheHits
      return cached.strip
  inc c.cacheMisses
  let cells = rawCellsForEntry(entry, c.cols)
  let strip = newStrip(cells)
  c.stripCache[key] = StripCacheEntry(
    inputHash: want, width: c.cols, strip: strip)
  return strip

# ----------------------------------------------------------------------------
# Compositing — stack entries by layer onto a buffer.
# ----------------------------------------------------------------------------

proc paintEntryOnto(buf: var ScreenBuffer; strip: Strip; entry: LayoutEntry;
                    cols: int) =
  ## Stamp the strip's cells onto the buffer at the entry's row. Cells
  ## that fall on transparent (default-bg, space-rune) positions are
  ## passed through; if the entry has `fillBackground`, the entry's
  ## styled blanks overwrite whatever is there. This is what gives a
  ## modal at layer=N the visual property of "masking" the layer below.
  ##
  ## Inline-row entries occupy ``[entry.col, entry.col + entry.width)``;
  ## the strip's cells outside that span are inert (plain spaces) and
  ## must not overwrite sibling entries on the same row. We clamp the
  ## fillBackground branch to the entry's declared span so a label
  ## entry on the left never masks the widget glyph entry on the right.
  if entry.row < 0 or entry.row >= buf.rowsCount: return
  let limit = min(strip.cells.len, cols)
  let spanStart = max(0, entry.col)
  let spanEnd = min(cols, max(0, entry.col + entry.width))
  var row = buf.rows[entry.row]
  for i in 0 ..< limit:
    let src = strip.cells[i]
    if src.width == 0:
      continue
    if entry.fillBackground and i >= spanStart and i < spanEnd:
      row.cells[i] = src
    else:
      if src.rune.int32 != 0 and src.rune != Rune(' '.ord):
        row.cells[i] = src
      elif src.fg != defaultColor() or src.bg != defaultColor() or
           src.attrs != {}:
        row.cells[i] = src
  recomputeCache(row)
  buf.rows[entry.row] = row

proc render*(c: Compositor; root: TerminalNode): ScreenBuffer =
  ## Walk the tree, flatten to layered entries, sort by layer (stable
  ## within layer), and composite onto a fresh buffer. The strip cache
  ## absorbs the per-entry cell construction on hits.
  var buf = newScreenBuffer(c.cols, c.rows)
  if root == nil: return buf
  var entries = walkLayoutClean(root, c.cols)
  for i in 1 ..< entries.len:
    var j = i
    while j > 0 and entries[j - 1].layer > entries[j].layer:
      let tmp = entries[j - 1]
      entries[j - 1] = entries[j]
      entries[j] = tmp
      dec j
  for entry in entries:
    if entry.row >= c.rows: continue
    let strip = stripForEntry(c, entry)
    paintEntryOnto(buf, strip, entry, c.cols)
  buf

# ----------------------------------------------------------------------------
# Region coalescing
# ----------------------------------------------------------------------------

proc coalesce*(regions: seq[CellRegion]): seq[CellRegion] =
  ## Merge adjacent regions on the same row into one. Input order is
  ## assumed to be (row asc, col asc). Output preserves that order with
  ## `r.col + r.width == next.col` runs joined.
  result = @[]
  for r in regions:
    if result.len > 0:
      let last = result[^1]
      if last.row == r.row and last.col + last.width == r.col:
        var merged = last
        merged.width = last.width + r.width
        merged.cells = last.cells & r.cells
        result[^1] = merged
        continue
    result.add r

proc diffRegions*(a, b: ScreenBuffer): seq[CellRegion] =
  ## Compute the coalesced dirty-region set turning `a` into `b`. This
  ## is the M8 entry point that the paint loop uses; keeping it public
  ## lets unit tests exercise the merging logic in isolation.
  let raw = diff(a, b)
  coalesce(raw)

# ----------------------------------------------------------------------------
# SGR-aware byte emission
# ----------------------------------------------------------------------------

proc cellStyle(cell: Cell): Style {.inline.} =
  newStyle(cell.fg, cell.bg, cell.attrs)

proc emitRegion*(prev: Style; region: CellRegion):
                tuple[bytes: string; trailing: Style] =
  ## Encode one dirty region as a minimal SGR-aware byte run. The
  ## output is `cursorTo(row, col)` followed by:
  ##
  ##   - one SGR transition per *style change* — cells that share the
  ##     trailing style emit only their UTF-8 rune,
  ##   - utf-8 payload for each cell (ghost trailing-halves of width-2
  ##     glyphs are skipped; the wide rune occupied both columns).
  ##
  ## Returns the resulting bytes and the trailing style so successive
  ## regions on the same row can keep emitting minimal transitions.
  result.bytes = cursorTo(region.row, region.col)
  result.trailing = prev
  for cell in region.cells:
    if cell.width == 0:
      continue
    let target = cellStyle(cell)
    let sgr = renderSgr(result.trailing, target)
    if sgr.len > 0:
      result.bytes.add sgr
      result.trailing = target
    if cell.rune.int32 != 0:
      result.bytes.add toUTF8(cell.rune)
    else:
      result.bytes.add ' '

proc emitRow*(prev: Style; regions: seq[CellRegion]):
             tuple[bytes: string; trailing: Style] =
  ## Encode every region in `regions` (assumed to be on the same row,
  ## col-ascending) using `emitRegion` and concatenate the byte runs.
  ## The trailing style is threaded so adjacent regions never re-emit
  ## an unchanged SGR.
  result.bytes = ""
  result.trailing = prev
  for r in regions:
    let (bytes, after) = emitRegion(result.trailing, r)
    result.bytes.add bytes
    result.trailing = after

# ----------------------------------------------------------------------------
# Paint — the headline entry point.
# ----------------------------------------------------------------------------

proc paint*(c: Compositor; root: TerminalNode; driver: HeadlessDriver) =
  ## Render the tree, diff against `lastBuffer`, and emit the minimal
  ## byte sequence that turns the terminal screen into the new buffer.
  ##
  ## Idle path: when the new buffer is byte-equivalent to the last
  ## paint, no driver write happens at all. Tests that "advance the
  ## tick 100x without input" rely on this for the 0% idle CPU
  ## guarantee.
  let buf = c.render(root)
  if c.initialPainted:
    let regions = coalesce(diff(c.lastBuffer, buf))
    c.lastDirty = regions
    if regions.len == 0:
      c.lastBuffer = buf
      return
    var prev = defaultStyle()
    var i = 0
    while i < regions.len:
      let row = regions[i].row
      var j = i
      while j < regions.len and regions[j].row == row:
        inc j
      let rowRegions = regions[i ..< j]
      let (bytes, after) = emitRow(prev, rowRegions)
      driver.writeRaw(bytes)
      prev = after
      i = j
    for r in 0 ..< buf.rowsCount:
      driver.buffer.setRow(r, buf.rows[r])
    c.lastBuffer = buf
  else:
    let regions = coalesce(diff(c.lastBuffer, buf))
    c.lastDirty = regions
    driver.paintBuffer(buf)
    c.lastBuffer = buf
    c.initialPainted = true

# ----------------------------------------------------------------------------
# Layout-region introspection
# ----------------------------------------------------------------------------

proc collectDescendantIds(n: TerminalNode; acc: var seq[int]) =
  if n == nil: return
  acc.add n.id
  for c in n.children:
    collectDescendantIds(c, acc)

proc layoutRegionFor*(c: Compositor; root: TerminalNode; nodeId: int):
                    tuple[row, col, width, height: int] =
  ## Look up the rectangle a node occupied in the most recent walk.
  ## Returns a zero-rect when the node didn't render. The lookup is
  ## fresh per call (no caching) so tree mutations between paints
  ## reflect immediately.
  ##
  ## When the requested node itself doesn't appear in the layout
  ## entries (e.g. a container `div` whose children are mixed boxes
  ## that recurse instead of collapsing into a single row), the
  ## bounding rectangle of all descendant entries is returned. This
  ## gives every widget a meaningful layout region even when its
  ## outer node doesn't emit a layout entry directly.
  result = (row: 0, col: 0, width: 0, height: 0)
  if root == nil: return
  let entries = walkLayoutClean(root, c.cols)
  for entry in entries:
    if entry.nodeId == nodeId:
      result = (row: entry.row, col: entry.col,
                width: entry.width, height: 1)
      return
  # Fallback: bounding rect over descendants.
  proc findNode(n: TerminalNode; id: int): TerminalNode =
    if n == nil: return nil
    if n.id == id: return n
    for c in n.children:
      let m = findNode(c, id)
      if m != nil: return m
    return nil
  let target = findNode(root, nodeId)
  if target == nil: return
  var ids: seq[int] = @[]
  collectDescendantIds(target, ids)
  if ids.len == 0: return
  var minRow = high(int)
  var maxRow = low(int)
  var minCol = high(int)
  var maxRight = low(int)
  var found = false
  for entry in entries:
    if entry.nodeId in ids:
      found = true
      if entry.row < minRow: minRow = entry.row
      if entry.row > maxRow: maxRow = entry.row
      if entry.col < minCol: minCol = entry.col
      let right = entry.col + entry.width
      if right > maxRight: maxRight = right
  if not found: return
  result = (row: minRow, col: minCol,
            width: maxRight - minCol,
            height: maxRow - minRow + 1)

proc nodesInRenderOrder*(root: TerminalNode): seq[int] =
  ## Walk the tree in the same order `render` will composite and
  ## return the node ids. Useful for snapshot annotations and the
  ## introspection dump.
  result = @[]
  if root == nil: return
  let entries = walkLayoutClean(root, 80)
  for entry in entries:
    result.add entry.nodeId
