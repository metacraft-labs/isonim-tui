## Cell-snap projection on top of isonim's `LayoutEngine`.
##
## Yoga is a *float-pixel* engine: its results are floats and assume one
## "pixel" = one device pixel. Terminals are integer-cell grids, so the
## TUI cannot ship a Yoga frame to the compositor unmodified — we have
## to *snap* the float rectangles to integer cells while preserving two
## invariants:
##
##   I1. Every node's `width + offset` must equal the parent's
##       `width + offset`. No leftover slack, no overlap.
##   I2. Adjacent siblings must not produce sub-cell rounding gaps.
##       (e.g. three 1fr siblings in a 91-cell parent → 30 / 30 / 31,
##       summing exactly to 91.)
##
## The rounding rule that achieves both is "ceiling for total, floor for
## offsets, last sibling absorbs slack". Documented in the milestone.
##
## *Charter §1*: every public type here is a value `object` (or plain
## enum). The wrapper around `LayoutEngine` is itself a `ref object`
## because it owns the underlying engine (which is also `ref`); but its
## API hands back value `CellRect` records.
##
## *Double-width awareness*: when a node carries text, the TUI port can
## set its `min-width` from `text/width.displayWidth` so Yoga reserves
## the right number of cells. Helpers below (`reserveTextCells`,
## `measureTextCells`) make that explicit.
##
## *Integration with isonim/layout/layout_engine.nim*: the helpers
## proposed for upstream (`calculateLayoutInCells`, `snapToCells`) live
## here today. The intent (per M3) is to upstream these into
## `LayoutEngine` as `proc`s once the API stabilises; the TUI keeps a
## thin re-export so callers don't have to switch imports later.

import std/[math, tables]

import isonim/layout/layout_engine
import isonim/layout/yoga_bindings

import ../text/width

export layout_engine.LayoutEngine, layout_engine.LayoutResult,
       layout_engine.newLayoutEngine, layout_engine.registerNode,
       layout_engine.addChild, layout_engine.removeChild,
       layout_engine.insertChildBefore, layout_engine.setLayoutStyle,
       layout_engine.calculateLayout, layout_engine.getLayout,
       layout_engine.allLayouts, layout_engine.parentIndex,
       layout_engine.freeAll

# ----------------------------------------------------------------------------
# Public value types
# ----------------------------------------------------------------------------

type
  CellRect* = object
    ## A snapped rectangle in *cell coordinates*. `row` / `col` are 0-based
    ## offsets from the parent's top-left; `width` / `height` are cell
    ## counts (always non-negative).
    col*: int
    row*: int
    width*: int
    height*: int

  SnapPolicy* = enum
    ## How rounding error is distributed between siblings.
    spLastAbsorbsSlack    ## Default: floor each sibling, last gets the
                          ## remainder. Keeps total exact.
    spDistributeRoundDown ## Floor each sibling; round error truncated.
    spDistributeRoundUp   ## Ceil each sibling; over-allocation possible.

  TerminalLayout* = ref object
    ## A wrapper around `LayoutEngine` that runs Yoga measurement in
    ## "cell units" (1 cell = 1 logical pixel) and projects the results
    ## back into snapped integer cell rectangles.
    ##
    ## Holds a reference to the underlying `LayoutEngine` (Yoga FFI) and
    ## a per-handle override of "minimum cell width reserved for this
    ## node's text" so double-width characters get the right column
    ## allocation.
    engine*: LayoutEngine
    cols*: int
    rows*: int
    policy*: SnapPolicy
    snapped*: Table[int64, CellRect]  ## handle → snapped rect (last layout)
    yogaRaw*: Table[int64, LayoutResult] ## handle → raw float result

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newTerminalLayout*(cols, rows: int;
                        policy: SnapPolicy = spLastAbsorbsSlack):
                        TerminalLayout =
  ## Construct a fresh `TerminalLayout` wrapping a fresh `LayoutEngine`.
  TerminalLayout(
    engine: newLayoutEngine(),
    cols: cols, rows: rows,
    policy: policy,
    snapped: initTable[int64, CellRect](),
    yogaRaw: initTable[int64, LayoutResult]())

proc newTerminalLayout*(engine: LayoutEngine; cols, rows: int;
                        policy: SnapPolicy = spLastAbsorbsSlack):
                        TerminalLayout =
  ## Wrap an existing `LayoutEngine` (e.g. shared with isonim-cocoa).
  TerminalLayout(
    engine: engine, cols: cols, rows: rows, policy: policy,
    snapped: initTable[int64, CellRect](),
    yogaRaw: initTable[int64, LayoutResult]())

# ----------------------------------------------------------------------------
# Text-cell reservation (double-width awareness)
# ----------------------------------------------------------------------------

proc measureTextCells*(text: string): int =
  ## Number of terminal cells needed to render `text`. East-Asian-wide
  ## glyphs and emoji ZWJ families count as 2 each; combining marks are
  ## 0; the rest are 1. Backed by `text/width.displayWidth`.
  width.displayWidth(text)

proc reserveTextCells*(layout: TerminalLayout; viewHandle: int64;
                       text: string) =
  ## Reserve `displayWidth(text)` cells of width and 1 cell of height
  ## for the node identified by `viewHandle`. Sets the Yoga node's
  ## `min-width`/`min-height` so layouts that compute "intrinsic size"
  ## (e.g. Auto rows in a grid template) get the right number even when
  ## the node is multi-codepoint with a single grapheme cluster.
  let cells = measureTextCells(text)
  if cells <= 0:
    return
  layout.engine.setLayoutStyle(viewHandle, "min-width", $cells)
  layout.engine.setLayoutStyle(viewHandle, "min-height", "1")

# ----------------------------------------------------------------------------
# Snap rule helpers
# ----------------------------------------------------------------------------

proc snapTotal(value: float): int {.inline.} =
  ## Total dimension uses *ceiling*: a node that needs 0.6 cells worth
  ## of content reserves 1 cell. Avoids accidental clip.
  int(ceil(value - 1e-6))

proc snapOffset(value: float): int {.inline.} =
  ## Offsets use *floor*: an offset of 0.6 cells lands on column 0.
  int(floor(value + 1e-6))

proc snapToCells*(rect: LayoutResult): CellRect =
  ## Stand-alone snap of a single Yoga `LayoutResult` (used when no
  ## sibling-context is required, e.g. for the root). The companion
  ## `snapSiblings` distributes rounding error between adjacent
  ## children so total widths still match the parent.
  CellRect(col: snapOffset(rect.x),
           row: snapOffset(rect.y),
           width: snapTotal(rect.width),
           height: snapTotal(rect.height))

# ----------------------------------------------------------------------------
# Sibling-aware snapping (distributes rounding error)
# ----------------------------------------------------------------------------

type
  Axis* = enum
    axHorizontal
    axVertical

proc distributeError(parentSize: int; childRaws: openArray[float];
                     policy: SnapPolicy): seq[int] =
  ## Given the parent's *integer* size on an axis and each child's
  ## *float* size on the same axis, return a seq of integer sizes whose
  ## sum equals `parentSize` (under `spLastAbsorbsSlack`).
  ##
  ## We floor each child to capture its exact integer share, accumulate
  ## the fractional error, and hand the leftover cells to the last
  ## non-zero child(ren). This is what produces 30/30/31 from
  ## (91, [30.333, 30.333, 30.333]).
  result = newSeq[int](childRaws.len)
  if childRaws.len == 0:
    return
  var floors = newSeq[int](childRaws.len)
  var fracs = newSeq[float](childRaws.len)
  var floorSum = 0
  for i, raw in childRaws:
    let f = int(floor(raw + 1e-6))
    floors[i] = max(0, f)
    fracs[i] = raw - float(f)
    floorSum += floors[i]
  case policy
  of spDistributeRoundDown:
    for i in 0 ..< floors.len: result[i] = floors[i]
  of spDistributeRoundUp:
    for i in 0 ..< floors.len:
      result[i] = floors[i] + (if fracs[i] > 1e-6: 1 else: 0)
  of spLastAbsorbsSlack:
    var remaining = max(0, parentSize - floorSum)
    for i in 0 ..< floors.len:
      result[i] = floors[i]
    # Hand remaining cells out to the largest fractional residues first
    # (floor-with-largest-remainder rule). This deterministic rule
    # ensures (30.333, 30.333, 30.333) + 1 leftover lands on the last
    # sibling rather than splitting capriciously.
    var indices: seq[int] = @[]
    for i in 0 ..< floors.len:
      if childRaws[i] > 0.0: indices.add i
    # Sort indices by descending fractional residue, ties broken by
    # later index (matches "last sibling absorbs slack" intent).
    proc cmp(a, b: int): int =
      let af = fracs[a]
      let bf = fracs[b]
      if af > bf + 1e-9: -1
      elif af < bf - 1e-9: 1
      else:
        if a > b: -1 else: 1
    # Insertion sort (n is small; siblings rarely exceed double digits).
    for i in 1 ..< indices.len:
      var j = i
      while j > 0 and cmp(indices[j], indices[j - 1]) < 0:
        let tmp = indices[j - 1]
        indices[j - 1] = indices[j]
        indices[j] = tmp
        dec j
    var k = 0
    while remaining > 0 and indices.len > 0:
      result[indices[k mod indices.len]] += 1
      dec remaining
      inc k

# ----------------------------------------------------------------------------
# calculateLayoutInCells — the headline entry point
# ----------------------------------------------------------------------------

proc recordRaw(layout: TerminalLayout; idx: int) =
  ## Cache the raw Yoga rect for a single node by idx.
  let node = layout.engine.nodes[idx]
  layout.yogaRaw[node.viewHandle] = LayoutResult(
    x: float(YGNodeLayoutGetLeft(node.yogaNode)),
    y: float(YGNodeLayoutGetTop(node.yogaNode)),
    width: float(YGNodeLayoutGetWidth(node.yogaNode)),
    height: float(YGNodeLayoutGetHeight(node.yogaNode)))

proc snapTreeAt(layout: TerminalLayout; idx: int;
                ownRect: CellRect) =
  ## Recursively snap a Yoga sub-tree. The caller has already determined
  ## this node's snapped rectangle (`ownRect`) and stored it in
  ## `layout.snapped`. This proc:
  ##
  ##   1. Reads each child's raw Yoga rect.
  ##   2. Decides whether children form a horizontal or vertical stack
  ##      (or neither — e.g. absolute-positioned).
  ##   3. Distributes the rounding error so child sizes sum to
  ##      `ownRect.width` (horizontal stack) or `ownRect.height`
  ##      (vertical stack).
  ##   4. Computes a snapped CellRect for each child, stores it, and
  ##      recurses.
  if idx < 0 or idx >= layout.engine.nodes.len:
    return
  let node = layout.engine.nodes[idx]
  if node.children.len == 0:
    return

  # Collect child raw widths/heights/offsets on each axis.
  var rawX: seq[float] = @[]
  var rawY: seq[float] = @[]
  var rawW: seq[float] = @[]
  var rawH: seq[float] = @[]
  for childIdx in node.children:
    let cn = layout.engine.nodes[childIdx]
    rawX.add float(YGNodeLayoutGetLeft(cn.yogaNode))
    rawY.add float(YGNodeLayoutGetTop(cn.yogaNode))
    rawW.add float(YGNodeLayoutGetWidth(cn.yogaNode))
    rawH.add float(YGNodeLayoutGetHeight(cn.yogaNode))
    recordRaw(layout, childIdx)

  # Detect "stack on horizontal axis" by checking whether children
  # share the same y. If so, we distribute width error among them so
  # the row exactly matches `ownRect.width`.
  var sameY = true
  if rawY.len > 1:
    for i in 1 ..< rawY.len:
      if abs(rawY[i] - rawY[0]) > 0.5:
        sameY = false
        break
  var sameX = true
  if rawX.len > 1:
    for i in 1 ..< rawX.len:
      if abs(rawX[i] - rawX[0]) > 0.5:
        sameX = false
        break

  var snappedW = newSeq[int](node.children.len)
  var snappedH = newSeq[int](node.children.len)
  if sameY and not sameX:
    # Horizontal stack: distribute width error.
    snappedW = distributeError(ownRect.width, rawW, layout.policy)
    for i in 0 ..< rawH.len: snappedH[i] = snapTotal(rawH[i])
  elif sameX and not sameY:
    # Vertical stack: distribute height error.
    snappedH = distributeError(ownRect.height, rawH, layout.policy)
    for i in 0 ..< rawW.len: snappedW[i] = snapTotal(rawW[i])
  else:
    for i in 0 ..< rawW.len:
      snappedW[i] = snapTotal(rawW[i])
      snappedH[i] = snapTotal(rawH[i])

  # Compute snapped offsets so children chain end-to-end (relative to
  # the parent's origin).
  var snappedX = newSeq[int](node.children.len)
  var snappedY = newSeq[int](node.children.len)
  if sameY and not sameX:
    var cursor = 0
    for i in 0 ..< node.children.len:
      snappedX[i] = cursor
      snappedY[i] = snapOffset(rawY[i])
      cursor += snappedW[i]
  elif sameX and not sameY:
    var cursor = 0
    for i in 0 ..< node.children.len:
      snappedX[i] = snapOffset(rawX[i])
      snappedY[i] = cursor
      cursor += snappedH[i]
  else:
    for i in 0 ..< node.children.len:
      snappedX[i] = snapOffset(rawX[i])
      snappedY[i] = snapOffset(rawY[i])

  for i, childIdx in node.children:
    let cn = layout.engine.nodes[childIdx]
    let childRect = CellRect(
      col: ownRect.col + snappedX[i],
      row: ownRect.row + snappedY[i],
      width: snappedW[i],
      height: snappedH[i])
    layout.snapped[cn.viewHandle] = childRect
    snapTreeAt(layout, childIdx, childRect)

proc calculateLayoutInCells*(layout: TerminalLayout) =
  ## Run Yoga measurement at the configured terminal size, then snap
  ## every node's float rectangle to integer cells. After this call,
  ## `cellRect(handle)` returns the snapped rect for any registered
  ## handle.
  ##
  ## This is the headline helper proposed for upstream into
  ## `LayoutEngine`. Today it lives in the TUI port; the milestone
  ## records the upstream PR as deferred.
  if layout.engine.nodes.len == 0:
    return
  layout.engine.calculateLayout(float(layout.cols), float(layout.rows))
  layout.snapped.clear()
  layout.yogaRaw.clear()
  # Seed: snap the root to (0, 0, cols, rows). The root carries the
  # parent dimensions; everything below it is computed relative.
  let rootNode = layout.engine.nodes[0]
  recordRaw(layout, 0)
  let rootRect = CellRect(col: 0, row: 0,
                          width: layout.cols, height: layout.rows)
  layout.snapped[rootNode.viewHandle] = rootRect
  snapTreeAt(layout, 0, rootRect)

proc cellRect*(layout: TerminalLayout; viewHandle: int64): CellRect =
  ## The snapped rectangle for a registered handle. Returns a zero-rect
  ## if the handle is unknown or the layout hasn't been computed yet.
  if viewHandle in layout.snapped:
    return layout.snapped[viewHandle]
  return CellRect()

proc rawLayout*(layout: TerminalLayout; viewHandle: int64): LayoutResult =
  ## The raw Yoga float result. Useful for tests asserting "Yoga said
  ## 26.4 → snap said 26".
  if viewHandle in layout.yogaRaw:
    return layout.yogaRaw[viewHandle]
  return LayoutResult()

# ----------------------------------------------------------------------------
# Convenience helpers
# ----------------------------------------------------------------------------

proc registerCellNode*(layout: TerminalLayout; viewHandle: int64): int
                     {.discardable.} =
  ## Register a node and return its index. Mirrors
  ## `LayoutEngine.registerNode` but kept here so user code can talk to
  ## the wrapper end-to-end.
  layout.engine.registerNode(viewHandle)

proc setStyle*(layout: TerminalLayout; viewHandle: int64;
               prop, value: string) =
  layout.engine.setLayoutStyle(viewHandle, prop, value)

proc childOf*(layout: TerminalLayout; parent, child: int64) =
  ## Append `child` to `parent` in the underlying engine.
  layout.engine.addChild(parent, child)

proc childOfBefore*(layout: TerminalLayout;
                    parent, child, refSibling: int64) =
  layout.engine.insertChildBefore(parent, child, refSibling)

proc dispose*(layout: TerminalLayout) =
  ## Free the underlying Yoga nodes. After dispose() the layout is
  ## no longer usable.
  layout.engine.freeAll()
  layout.snapped.clear()
  layout.yogaRaw.clear()
