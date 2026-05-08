## Reflow planner — compute deltas between successive layouts.
##
## Port of Textual's `textual/_arrange.py` (407 LOC). When an upstream
## signal mutates a node's text or style we need to know *which* nodes
## actually changed dimension or position; only those nodes contribute
## dirty regions to the compositor. Repaint amplification — re-painting
## an entire panel because one cell changed — is what `arrange` exists
## to prevent.
##
## A `LayoutSnapshot` captures the snapped rectangle for every handle in
## a layout. `arrange(prev, next)` diffs two snapshots and produces an
## `ArrangeDelta` with three sets:
##
##   * `hidden`    — handles present in `prev` but not in `next`.
##   * `shown`     — handles new in `next`.
##   * `resized`   — handles present in both whose rect changed.
##
## A handle whose rect is *identical* between snapshots appears in
## *none* of the sets — that's the contract that lets the compositor
## skip its strips entirely.

import std/[tables, sets, hashes]

import ./terminal_layout

type
  LayoutSnapshot* = object
    ## Frozen snapped rectangles for every handle in a layout pass.
    ## Value type for charter compliance; the underlying table is
    ## copied by-value when assigned.
    rects*: Table[int64, CellRect]

  ArrangeDelta* = object
    ## What changed between two snapshots. Sets are kept as `seq` so
    ## ordering is deterministic; downstream callers can convert to
    ## HashSet if they need set semantics.
    hidden*: seq[int64]
    shown*: seq[int64]
    resized*: seq[int64]

# ----------------------------------------------------------------------------
# Snapshot construction
# ----------------------------------------------------------------------------

proc snapshot*(layout: TerminalLayout): LayoutSnapshot =
  ## Snapshot every handle that has a snapped rect in `layout`.
  result = LayoutSnapshot(rects: initTable[int64, CellRect]())
  for handle, rect in layout.snapped.pairs:
    result.rects[handle] = rect

proc snapshotFromTable*(rects: Table[int64, CellRect]): LayoutSnapshot =
  LayoutSnapshot(rects: rects)

# ----------------------------------------------------------------------------
# Delta computation
# ----------------------------------------------------------------------------

proc `==`*(a, b: CellRect): bool {.inline.} =
  a.col == b.col and a.row == b.row and a.width == b.width and
    a.height == b.height

proc hash*(r: CellRect): Hash {.inline.} =
  result = hash(r.col)
  result = result !& hash(r.row)
  result = result !& hash(r.width)
  result = result !& hash(r.height)
  result = !$result

proc arrange*(prev, next: LayoutSnapshot): ArrangeDelta =
  ## Diff two snapshots. Order:
  ##
  ##   * `hidden` — sorted ascending by handle (deterministic).
  ##   * `shown`  — sorted ascending by handle.
  ##   * `resized` — sorted ascending by handle.
  result = ArrangeDelta(hidden: @[], shown: @[], resized: @[])

  var prevHandles: seq[int64] = @[]
  for h in prev.rects.keys: prevHandles.add h
  var nextHandles: seq[int64] = @[]
  for h in next.rects.keys: nextHandles.add h

  let prevSet = block:
    var s = initHashSet[int64]()
    for h in prevHandles: s.incl h
    s
  let nextSet = block:
    var s = initHashSet[int64]()
    for h in nextHandles: s.incl h
    s

  for h in prevHandles:
    if h notin nextSet:
      result.hidden.add h
  for h in nextHandles:
    if h notin prevSet:
      result.shown.add h
    else:
      let pr = prev.rects[h]
      let nr = next.rects[h]
      if not (pr == nr):
        result.resized.add h

  # Deterministic order by handle.
  proc cmpInt64(a, b: int64): int =
    if a < b: -1 elif a > b: 1 else: 0
  template sortBy(s: seq[int64]) =
    for i in 1 ..< s.len:
      var j = i
      while j > 0 and cmpInt64(s[j], s[j - 1]) < 0:
        let tmp = s[j - 1]
        s[j - 1] = s[j]
        s[j] = tmp
        dec j
  sortBy(result.hidden)
  sortBy(result.shown)
  sortBy(result.resized)

# ----------------------------------------------------------------------------
# Convenience: empty / equality
# ----------------------------------------------------------------------------

proc isEmpty*(d: ArrangeDelta): bool {.inline.} =
  ## True iff the delta is the zero diff (no hidden/shown/resized).
  d.hidden.len == 0 and d.shown.len == 0 and d.resized.len == 0

proc len*(d: ArrangeDelta): int {.inline.} =
  d.hidden.len + d.shown.len + d.resized.len
