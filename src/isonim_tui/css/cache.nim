## isonim_tui/css/cache.nim
##
## Per-widget computed-style cache. Mirrors a small subset of Textual's
## `_styles_cache.py`: when a node is asked for its computed style, we
## look it up by `(nodeId, stylesheetRevision, pseudoStateBits)` and
## return the cached `Styles` if present.
##
## Invalidation:
##   - Stylesheet revision change invalidates every entry transitively
##     (we drop entries with mismatched revision lazily on lookup).
##   - Per-node invalidation drops only the entries for that node id.
##   - Pseudo-state transition: the next lookup uses a different cache
##     key so the old entry is harmless until evicted.

import std/[tables, hashes]
import ./styles
import ./match
import ./stylesheet

type
  StyleCacheKey* = object
    nodeId*: int
    revision*: int
    pseudo*: set[PseudoState]

  StyleCacheStats* = object
    hits*: int
    misses*: int
    invalidations*: int

  StylesCache* = ref object
    entries*: Table[StyleCacheKey, Styles]
    stats*: StyleCacheStats

proc hash*(k: StyleCacheKey): Hash =
  result = hash(k.nodeId)
  result = result !& hash(k.revision)
  var psBits = 0
  for ps in k.pseudo: psBits = psBits or (1 shl ord(ps))
  result = result !& hash(psBits)
  result = !$result

proc `==`*(a, b: StyleCacheKey): bool =
  a.nodeId == b.nodeId and a.revision == b.revision and a.pseudo == b.pseudo

proc newStylesCache*(): StylesCache =
  StylesCache(entries: initTable[StyleCacheKey, Styles]())

proc lookup*(cache: StylesCache; key: StyleCacheKey;
             sheet: Stylesheet; ctx: NodeContext;
             parentPseudo: TableRef[int, set[PseudoState]] = nil): Styles =
  ## Look up by key. On miss, compute via the cascade and store. On
  ## stylesheet-revision mismatch, the new key has a different
  ## `revision` so the entry simply isn't found — old entries linger
  ## until `prune` runs.
  if key in cache.entries:
    inc cache.stats.hits
    return cache.entries[key]
  inc cache.stats.misses
  let computed = computeStyles(sheet, ctx, parentPseudo)
  cache.entries[key] = computed
  computed

proc invalidateNode*(cache: StylesCache; nodeId: int) =
  ## Drop every entry for `nodeId` (across all revisions / pseudo sets).
  var toDrop: seq[StyleCacheKey]
  for k in cache.entries.keys:
    if k.nodeId == nodeId: toDrop.add(k)
  for k in toDrop:
    cache.entries.del(k)
    inc cache.stats.invalidations

proc invalidateAll*(cache: StylesCache) =
  cache.stats.invalidations += cache.entries.len
  cache.entries.clear()

proc prune*(cache: StylesCache; currentRevision: int) =
  ## Drop entries that don't match the current stylesheet revision.
  ## Called periodically (e.g. once per render frame) to bound memory.
  var toDrop: seq[StyleCacheKey]
  for k in cache.entries.keys:
    if k.revision != currentRevision: toDrop.add(k)
  for k in toDrop:
    cache.entries.del(k)
    inc cache.stats.invalidations

proc resetStats*(cache: StylesCache) =
  cache.stats = StyleCacheStats()
