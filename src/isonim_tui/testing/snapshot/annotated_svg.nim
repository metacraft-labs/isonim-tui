## Annotated SVG — base SVG plus overlay rects for layout regions,
## focus ring, dirty regions, layer stack, and scroll regions.
##
## M2 introduced overlays for widget bounding boxes / focus ring /
## dirty-region heatmap. M25 expands the set with toggleable flags so
## tests can isolate one overlay class at a time and the live debug
## SVG viewer can pick which annotations to render.

import std/[strutils, tables]

import ../../cells
import ../../renderer
import ../../compositor
import ./svg as svgMod

const cellWidth = 8
const cellHeight = 16

type
  AnnotationOverlay* = enum
    ## Flags selecting which overlay rects appear in the annotated
    ## SVG. Default behaviour (no flag set passed) keeps M2's behaviour
    ## of rendering boxes + focus + dirty.
    aoBoxes      ## Per-node bounding boxes (blue stroke)
    aoFocus      ## Focused-node ring (orange stroke)
    aoDirty      ## Compositor's last-dirty regions (red translucent)
    aoLayers     ## Layer-stack indicator (green dashed for layer > 0)
    aoScroll     ## Scroll-region marker (purple dashed for nodes
                 ## carrying overflow / scroll styles)

const defaultOverlays* = {aoBoxes, aoFocus, aoDirty}

proc rectStr(id: string; row, col, width, height: int; color: string;
             dashed: bool = false): string =
  let x = col * cellWidth
  let y = row * cellHeight
  let w = width * cellWidth
  let h = height * cellHeight
  var s = "  <rect id=\"" & id & "\" x=\"" & $x & "\" y=\"" & $y &
    "\" width=\"" & $w & "\" height=\"" & $h &
    "\" fill=\"none\" stroke=\"" & color & "\" stroke-width=\"1\""
  if dashed:
    s.add " stroke-dasharray=\"4,2\""
  s.add "/>"
  s

proc nodeHasScrollStyle(n: TerminalNode): bool =
  if n == nil: return false
  if "overflow" in n.styles:
    let v = n.styles["overflow"]
    if v == "auto" or v == "scroll": return true
  if "overflow-x" in n.styles:
    let v = n.styles["overflow-x"]
    if v == "auto" or v == "scroll": return true
  if "overflow-y" in n.styles:
    let v = n.styles["overflow-y"]
    if v == "auto" or v == "scroll": return true
  false

proc layerForNode(n: TerminalNode): int =
  if n == nil: return 0
  if "layer" in n.styles:
    try:
      return parseInt(n.styles["layer"])
    except CatchableError:
      return 0
  if "position" in n.styles and n.styles["position"] == "overlay":
    return 1
  0

proc collectNodes(n: TerminalNode; acc: var seq[TerminalNode]) =
  if n == nil: return
  acc.add n
  for c in n.children:
    collectNodes(c, acc)

proc encodeAnnotatedSvgWith*(buf: ScreenBuffer; root: TerminalNode;
                            comp: Compositor; focusedId: int;
                            overlays: set[AnnotationOverlay]): string =
  ## Overlay-aware encoder. The base SVG is the same plain encoding
  ## from `svg.nim`; overlays are appended only when the matching
  ## `AnnotationOverlay` flag is in `overlays`. Pass an empty set for
  ## a clean SVG; pass `defaultOverlays` for the M2 behaviour.
  let base = svgMod.encodeSvg(buf)
  let close = "</svg>\n"
  var head = base
  if base.endsWith(close):
    head = base[0 ..< base.len - close.len]
  var lines: seq[string] = @[]
  lines.add head
  if aoBoxes in overlays:
    let nodeIds = nodesInRenderOrder(root)
    for nid in nodeIds:
      let region = compositor.layoutRegionFor(comp, root, nid)
      if region.width == 0 or region.height == 0: continue
      lines.add rectStr("box-" & $nid, region.row, region.col,
                        region.width, region.height, "#3399ff")
  if aoFocus in overlays and focusedId != 0:
    let f = compositor.layoutRegionFor(comp, root, focusedId)
    if f.width > 0 and f.height > 0:
      lines.add rectStr("focus", f.row, f.col, f.width, f.height,
                        "#ff9900")
  if aoDirty in overlays:
    for region in comp.lastDirty:
      lines.add "  <rect id=\"dirty-" & $region.row & "-" & $region.col &
        "\" x=\"" & $(region.col * cellWidth) & "\" y=\"" &
        $(region.row * cellHeight) & "\" width=\"" &
        $(region.width * cellWidth) & "\" height=\"" & $cellHeight &
        "\" fill=\"#ff0000\" fill-opacity=\"0.2\"/>"
  if aoLayers in overlays:
    var allNodes: seq[TerminalNode] = @[]
    collectNodes(root, allNodes)
    for n in allNodes:
      let layer = layerForNode(n)
      if layer <= 0: continue
      let region = compositor.layoutRegionFor(comp, root, n.id)
      if region.width == 0 or region.height == 0: continue
      lines.add rectStr("layer-" & $n.id, region.row, region.col,
                        region.width, region.height, "#33aa33",
                        dashed = true)
  if aoScroll in overlays:
    var allNodes: seq[TerminalNode] = @[]
    collectNodes(root, allNodes)
    for n in allNodes:
      if not nodeHasScrollStyle(n): continue
      let region = compositor.layoutRegionFor(comp, root, n.id)
      if region.width == 0 or region.height == 0: continue
      lines.add rectStr("scroll-" & $n.id, region.row, region.col,
                        region.width, region.height, "#9933cc",
                        dashed = true)
  lines.add "</svg>"
  result = lines.join("\n") & "\n"

proc encodeAnnotatedSvg*(buf: ScreenBuffer; root: TerminalNode;
                        comp: Compositor; focusedId: int): string =
  ## Default-overlay variant — preserves the M2 surface. Equivalent to
  ## `encodeAnnotatedSvgWith(..., defaultOverlays)`.
  encodeAnnotatedSvgWith(buf, root, comp, focusedId, defaultOverlays)
