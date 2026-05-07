## Display-width and grapheme-cluster utilities.
##
## This module is the source of truth for "how many cells does this
## glyph occupy on a terminal" and "where do glyph cluster boundaries
## fall". Every later layer (Cell, Strip, Content, compositor) routes
## through these primitives.
##
## Backed by Unicode 16.0.0 tables generated from the vendored UCD by
## `tools/generate_unicode_tables.nim`. The tables are checked into the
## repo so builds are hermetic.
##
## Charter §1: every public type here is a value `object` (or plain
## enum). No `ref`, no raw `ptr`. Internally we use `seq[int32]` to
## hold cluster boundaries — those allocate via the GC but never escape
## as ref/ptr.

import std/unicode

import east_asian_width_table
import grapheme_break_table
import emoji_table
import incb_table

export east_asian_width_table, grapheme_break_table, emoji_table, incb_table

# ----------------------------------------------------------------------------
# Ambiguous-width configuration (thread-local; charter §1 — no global mutable
# state across threads)
# ----------------------------------------------------------------------------

type
  AmbiguousWidth* = enum
    awNarrow   ## Default: ambiguous-width characters render as 1 cell.
    awWide     ## CJK locale or user-configured: render as 2 cells.

var ambiguousWidth {.threadvar.}: AmbiguousWidth

proc setAmbiguousWidth*(mode: AmbiguousWidth) {.inline.} =
  ## Override the per-thread ambiguous-width policy. Default is `awNarrow`
  ## matching Textual's behaviour.
  ambiguousWidth = mode

proc getAmbiguousWidth*(): AmbiguousWidth {.inline.} =
  ambiguousWidth

# ----------------------------------------------------------------------------
# Single-rune display width
# ----------------------------------------------------------------------------

const
  ZeroWidthJoiner* = 0x200D
  ZeroWidthNonJoiner* = 0x200C
  VariationSelector15* = 0xFE0E   ## Text presentation selector
  VariationSelector16* = 0xFE0F   ## Emoji presentation selector

proc isZeroWidth(cp: int32): bool {.inline.} =
  ## Combining marks, ZWJ, ZWNJ, variation selectors, control formats, etc.
  ## Anything that contributes 0 cells on its own.
  if cp == 0: return true
  if cp < 0x20 or cp == 0x7F: return true   # C0 / DEL
  if cp >= 0x80 and cp <= 0x9F: return true  # C1 controls
  let gb = graphemeBreakKind(cp)
  case gb
  of gbExtend, gbZWJ, gbSpacingMark, gbPrepend, gbControl, gbCR, gbLF:
    return true
  else: discard
  # Hangul Jamo extending forms (T) attach to a preceding L/V, no width.
  if gb == gbT: return true
  return false

proc displayWidth*(r: Rune): int =
  ## Number of terminal cells a single rune occupies, *out of context*
  ## (i.e. without considering surrounding combining marks or ZWJ
  ## sequences). For full-fidelity width of a string, use
  ## `displayWidth(string)` which iterates by grapheme cluster.
  let cp = int32(r)
  if isZeroWidth(cp): return 0
  case eawClass(cp)
  of eawWide: return 2
  of eawAmbiguous:
    return (if ambiguousWidth == awWide: 2 else: 1)
  of eawHalf, eawNarrow:
    return 1

# ----------------------------------------------------------------------------
# Grapheme cluster iterator (UAX #29, Unicode 16)
# ----------------------------------------------------------------------------

# UAX #29 GB rules (subset we actually implement — every other pair breaks
# unconditionally per GB999):
#   GB1, GB2: at start/end → handled by the iterator wrapper.
#   GB3:  CR × LF       — never break inside a CRLF pair.
#   GB4:  Control / CR / LF ÷
#   GB5:  ÷ Control / CR / LF
#   GB6:  L × (L | V | LV | LVT)
#   GB7:  (LV | V) × (V | T)
#   GB8:  (LVT | T) × T
#   GB9:  × Extend, × ZWJ
#   GB9a: × SpacingMark
#   GB9b: Prepend ×
#   GB9c: \p{InCB=Consonant} [ \p{InCB=Extend} \p{InCB=Linker} ]* \p{InCB=Linker}
#         [ \p{InCB=Extend} \p{InCB=Linker} ]* × \p{InCB=Consonant}
#         (Indic conjunct break — Unicode 15.1+; we approximate with Extend
#         since InCB tables are not yet vendored. The corpus we ship covers
#         the common cases; remaining edge cases are documented.)
#   GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
#   GB12, GB13: regional-indicator pair (RI × RI) breaks every two RIs.
#   GB999: any other position breaks.

proc shouldBreak(prev, curr: int32; runeBuf: openArray[int32];
                 prevIdx: int): bool =
  ## Return whether a grapheme break occurs *between* runeBuf[prevIdx]
  ## and the next rune (curr). prev is provided for convenience but is
  ## redundant with runeBuf[prevIdx]; we keep both to minimise table
  ## lookups in the hot path.
  let pK = graphemeBreakKind(prev)
  let cK = graphemeBreakKind(curr)

  # GB3: CR × LF
  if pK == gbCR and cK == gbLF: return false
  # GB4: Control/CR/LF ÷
  if pK in {gbControl, gbCR, gbLF}: return true
  # GB5: ÷ Control/CR/LF
  if cK in {gbControl, gbCR, gbLF}: return true
  # GB6: L × (L|V|LV|LVT)
  if pK == gbL and cK in {gbL, gbV, gbLV, gbLVT}: return false
  # GB7: (LV|V) × (V|T)
  if pK in {gbLV, gbV} and cK in {gbV, gbT}: return false
  # GB8: (LVT|T) × T
  if pK in {gbLVT, gbT} and cK == gbT: return false
  # GB9: × Extend, × ZWJ
  if cK in {gbExtend, gbZWJ}: return false
  # GB9a: × SpacingMark
  if cK == gbSpacingMark: return false
  # GB9b: Prepend ×
  if pK == gbPrepend: return false
  # GB11: ExtPict Extend* ZWJ × ExtPict
  if pK == gbZWJ and isExtendedPictographic(curr):
    # walk back through Extend* to find an Extended_Pictographic
    var i = prevIdx - 1
    while i >= 0 and graphemeBreakKind(runeBuf[i]) == gbExtend:
      dec i
    if i >= 0 and isExtendedPictographic(runeBuf[i]):
      return false
  # GB9c: InCB=Consonant ([InCB=Extend|InCB=Linker]* InCB=Linker
  #        [InCB=Extend|InCB=Linker]*) × InCB=Consonant
  if inCBKind(curr) == incbConsonant:
    # Walk back through InCB={Extend,Linker} runs and look for at least
    # one Linker, anchored by an InCB=Consonant.
    var i = prevIdx
    var sawLinker = false
    while i >= 0:
      let k = inCBKind(runeBuf[i])
      if k == incbLinker:
        sawLinker = true
        dec i
      elif k == incbExtend:
        dec i
      else:
        break
    if sawLinker and i >= 0 and inCBKind(runeBuf[i]) == incbConsonant:
      return false
  # GB12/13: RI × RI; break every two RIs.
  if pK == gbRegionalIndicator and cK == gbRegionalIndicator:
    var riCount = 0
    var i = prevIdx
    while i >= 0 and graphemeBreakKind(runeBuf[i]) == gbRegionalIndicator:
      inc riCount
      dec i
    return (riCount mod 2) == 0
  # GB999
  return true

iterator graphemeClusters*(s: string): tuple[start, stop: int; text: string] =
  ## Yield (byteStart, byteStop, substring) for each grapheme cluster in
  ## `s`. `byteStop` is exclusive. The `text` slice can be hashed,
  ## width-measured, or copied into a Cell.
  ##
  ## Implementation: decode all runes (with byte spans) up front, then
  ## walk pairwise applying UAX #29. The runes-buffer is needed because
  ## GB11 looks back through Extend* and GB12/13 counts adjacent RIs.
  if s.len == 0:
    discard
  else:
    var runeBuf: seq[int32] = @[]
    var byteStart: seq[int] = @[]
    var byteEnd: seq[int] = @[]
    var i = 0
    while i < s.len:
      var r: Rune
      let bStart = i
      fastRuneAt(s, i, r, true)
      runeBuf.add(int32(r))
      byteStart.add(bStart)
      byteEnd.add(i)
    var clusterStart = 0
    var k = 1
    while k < runeBuf.len:
      if shouldBreak(runeBuf[k - 1], runeBuf[k], runeBuf, k - 1):
        let bs = byteStart[clusterStart]
        let be = byteStart[k]
        yield (bs, be, s[bs ..< be])
        clusterStart = k
      inc k
    if clusterStart < runeBuf.len:
      let bs = byteStart[clusterStart]
      let be = byteEnd[runeBuf.len - 1]
      yield (bs, be, s[bs ..< be])

iterator graphemeClusters*(runes: openArray[int32]):
    tuple[start, stop: int] =
  ## Same iterator over a pre-decoded rune sequence. Yields rune-index
  ## boundaries (start, stop). Useful when the caller already has
  ## int32 codepoints (e.g. driven by a fixture loader).
  if runes.len == 0:
    discard
  else:
    var clusterStart = 0
    var k = 1
    while k < runes.len:
      if shouldBreak(runes[k - 1], runes[k], runes, k - 1):
        yield (clusterStart, k)
        clusterStart = k
      inc k
    yield (clusterStart, runes.len)

# ----------------------------------------------------------------------------
# Display width of a string — grapheme-cluster-aware
# ----------------------------------------------------------------------------

proc clusterDisplayWidth*(cluster: string): int =
  ## Width of a single grapheme cluster. The cluster's first
  ## Extended_Pictographic / wide-base rune sets the width; combining
  ## marks and ZWJ inside contribute 0; an emoji-presentation variation
  ## selector (VS16) on a base that would otherwise be width 1 promotes
  ## it to width 2 (e.g. ✈️ → 2). VS15 (text presentation) keeps
  ## width 1. Regional-indicator pairs (flags) always render as width 2.
  if cluster.len == 0: return 0
  var first = true
  var width = 0
  var hasVs16 = false
  var hasVs15 = false
  var basePictographic = false
  var baseRegionalIndicator = false
  var baseExtendedPictographic = false
  for r in runes(cluster):
    let cp = int32(r)
    if first:
      width = displayWidth(r)
      basePictographic = isExtendedPictographic(cp)
      baseExtendedPictographic = basePictographic
      baseRegionalIndicator =
        graphemeBreakKind(cp) == gbRegionalIndicator
      first = false
    else:
      if cp == VariationSelector16: hasVs16 = true
      elif cp == VariationSelector15: hasVs15 = true
  # VS16 promotes ambiguous/narrow Extended_Pictographic to width 2.
  if hasVs16 and basePictographic and width == 1:
    width = 2
  # Regional-indicator clusters (flags) always render as 2 cells.
  if baseRegionalIndicator:
    width = 2
  # Extended_Pictographic clusters with combining ZWJ joins (a ZWJ
  # family or a skin-tone modifier) always render as 2 cells regardless
  # of the base codepoint's EAW class.
  if baseExtendedPictographic and not hasVs15:
    # If there are extra runes (combining/ZWJ/modifier), force width 2.
    var extraRunes = 0
    for _ in runes(cluster):
      inc extraRunes
      if extraRunes > 1: break
    if extraRunes > 1: width = 2
  # VS15 (text) keeps width as base computed it (no promotion).
  discard hasVs15
  return width

proc displayWidth*(s: string): int =
  ## Total cell width of a string. Iterates by grapheme cluster so ZWJ
  ## families count as one wide glyph (width 2), not as the sum of
  ## codepoint widths.
  result = 0
  for c in graphemeClusters(s):
    result += clusterDisplayWidth(c.text)

proc graphemeClusterCount*(s: string): int =
  ## Number of grapheme clusters in the string.
  result = 0
  for _ in graphemeClusters(s):
    inc result
