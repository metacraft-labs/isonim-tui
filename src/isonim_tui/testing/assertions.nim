## Renderer-state assertions — M25 power tools.
##
## Three predicates that gate common renderer regressions:
##   * `assertNoOverlap` — every visible widget is contained within
##     the bounding rectangle of its parent. Catches layout bugs where
##     a child width-overflows its container.
##   * `assertSinglePassPaint` — a single paint cycle didn't trigger
##     another reflow. Catches infinite-loop reactive bugs where a
##     paint dirties a signal that re-dirties paint.
##   * `assertCacheHitRate(min)` — the strip cache's running hit
##     ratio is at least `min`. Gates strip-cache regressions.
##
## Each `assert*` proc returns a value-typed `AssertResult` rather than
## raising an exception so tests can pattern-match on the offenders
## list. A convenience wrapper that does raise is provided for callers
## that prefer the unittest-friendly form.
##
## Charter §1: pure value-typed result objects, no `ref` types.

import std/[strutils, tables]

import ../renderer
import ../compositor
import ./harness

type
  OverlapOffense* = object
    ## One node whose layout rectangle escapes its parent's
    ## rectangle. The fields hold both ids + both rectangles so the
    ## error message can show "child #N (12,5 8x1) escaped parent #M
    ## (10,5 5x1)".
    childId*: int
    parentId*: int
    childRow*, childCol*, childWidth*, childHeight*: int
    parentRow*, parentCol*, parentWidth*, parentHeight*: int

  AssertResult* = object
    ok*: bool
    message*: string
    overlaps*: seq[OverlapOffense]

  PaintAssertResult* = object
    ok*: bool
    message*: string
    initialDirtyRegions*: int
    secondPassDirtyRegions*: int

  CacheAssertResult* = object
    ok*: bool
    message*: string
    hits*: int
    misses*: int
    rate*: float
    minRate*: float

# ----------------------------------------------------------------------------
# assertNoOverlap
# ----------------------------------------------------------------------------

proc rectContains(parent: tuple[row, col, width, height: int];
                  child: tuple[row, col, width, height: int]): bool =
  ## Strict geometric containment: child's full rectangle fits inside
  ## parent's. A zero-width / zero-height child is treated as
  ## contained because a node with no rendered area can't visibly
  ## escape anything.
  if child.width == 0 or child.height == 0: return true
  if child.row < parent.row: return false
  if child.col < parent.col: return false
  if child.row + child.height > parent.row + parent.height: return false
  if child.col + child.width > parent.col + parent.width: return false
  true

proc effectiveRect(h: TerminalTestHarness; n: TerminalNode):
                  tuple[row, col, width, height: int] =
  ## Resolve the *layout-effective* rectangle for a node. Pulls the
  ## rect from the compositor's layout regions, then honours an
  ## explicit `data-test-bounds` attribute on the node when present
  ## — used by tests to inject deliberately misaligned geometry. The
  ## attribute format is `row,col,width,height` (four integers).
  result = layoutRegionFor(h.compositor, h.root, n.id)
  if "data-test-bounds" in n.attributes:
    let parts = n.attributes["data-test-bounds"].split(',')
    if parts.len == 4:
      try:
        result = (
          row: parseInt(parts[0].strip()),
          col: parseInt(parts[1].strip()),
          width: parseInt(parts[2].strip()),
          height: parseInt(parts[3].strip()))
      except CatchableError:
        discard

proc walkNoOverlap(h: TerminalTestHarness; n: TerminalNode;
                   acc: var seq[OverlapOffense]) =
  if n == nil: return
  let parentReg = effectiveRect(h, n)
  for c in n.children:
    let childReg = effectiveRect(h, c)
    # Skip non-rendered children (zero rect) — they can't overlap.
    if childReg.width == 0 or childReg.height == 0:
      walkNoOverlap(h, c, acc)
      continue
    if not rectContains(parentReg, childReg):
      acc.add OverlapOffense(
        childId: c.id, parentId: n.id,
        childRow: childReg.row, childCol: childReg.col,
        childWidth: childReg.width, childHeight: childReg.height,
        parentRow: parentReg.row, parentCol: parentReg.col,
        parentWidth: parentReg.width, parentHeight: parentReg.height)
    walkNoOverlap(h, c, acc)

proc assertNoOverlap*(h: TerminalTestHarness): AssertResult =
  ## Walk the tree and verify every child fits within its parent's
  ## bounding rectangle. The root is exempt (its parent is the
  ## terminal surface itself, which is implicitly the entire grid).
  result = AssertResult(ok: true, message: "", overlaps: @[])
  if h.root == nil: return
  walkNoOverlap(h, h.root, result.overlaps)
  if result.overlaps.len > 0:
    result.ok = false
    var msgs: seq[string] = @[]
    msgs.add "assertNoOverlap: " & $result.overlaps.len &
      " offending node(s):"
    for o in result.overlaps:
      msgs.add "  child #" & $o.childId &
        " (" & $o.childRow & "," & $o.childCol & " " &
        $o.childWidth & "x" & $o.childHeight & ") escapes" &
        " parent #" & $o.parentId &
        " (" & $o.parentRow & "," & $o.parentCol & " " &
        $o.parentWidth & "x" & $o.parentHeight & ")"
    result.message = msgs.join("\n")

# ----------------------------------------------------------------------------
# assertSinglePassPaint
# ----------------------------------------------------------------------------

proc assertSinglePassPaint*(h: TerminalTestHarness): PaintAssertResult =
  ## Run paint twice in a row and assert that the second paint produced
  ## *no* dirty regions. The contract: a flush should reach a fixpoint
  ## in one pass — if the first paint produced regions and the second
  ## one *also* produces non-empty dirty regions, something in the
  ## paint cycle is dirtying state.
  result = PaintAssertResult(ok: true, message: "",
                             initialDirtyRegions: 0,
                             secondPassDirtyRegions: 0)
  if h.root == nil: return
  # First paint (the harness has likely flushed already; flush again
  # to land in a known state).
  h.flush()
  result.initialDirtyRegions = h.compositor.lastDirty.len
  # Second paint with no input — should be idle.
  h.flush()
  result.secondPassDirtyRegions = h.compositor.lastDirty.len
  if result.secondPassDirtyRegions > 0:
    result.ok = false
    result.message = "assertSinglePassPaint: second paint produced " &
      $result.secondPassDirtyRegions &
      " dirty region(s) — paint did not converge in one pass"

# ----------------------------------------------------------------------------
# assertCacheHitRate
# ----------------------------------------------------------------------------

proc assertCacheHitRate*(h: TerminalTestHarness; minRate: float):
                       CacheAssertResult =
  ## The strip cache's hit / (hit + miss) ratio must be at least
  ## `minRate`. With zero cache lookups (no paints have run) the
  ## assertion vacuously passes — there's no regression to gate.
  let s = h.compositor.stats()
  let total = s.hits + s.misses
  let rate = if total == 0: 1.0 else: s.hits.float / total.float
  result = CacheAssertResult(
    ok: rate >= minRate,
    hits: s.hits, misses: s.misses, rate: rate, minRate: minRate)
  if not result.ok:
    result.message = "assertCacheHitRate: rate " &
      formatFloat(rate, ffDecimal, 4) &
      " < required " & formatFloat(minRate, ffDecimal, 4) &
      " (hits=" & $s.hits & " misses=" & $s.misses & ")"
