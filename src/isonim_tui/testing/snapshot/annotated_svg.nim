## Annotated SVG — base SVG plus overlay rects for layout regions,
## focus ring, and dirty regions.
##
## M2 deliverable lists overlays for widget bounding boxes / focus
## ring / dirty-region heatmap. The dirty-region overlay uses the
## compositor's `lastDirty` set; the focus overlay uses the harness's
## focused node id; the bounding boxes come from the placeholder
## layout (one row per visible node).

import std/[strutils]

import ../../cells
import ../../renderer
import ../../compositor
import ./svg as svgMod

const cellWidth = 8
const cellHeight = 16

proc rectStr(id: string; row, col, width, height: int; color: string): string =
  let x = col * cellWidth
  let y = row * cellHeight
  let w = width * cellWidth
  let h = height * cellHeight
  "  <rect id=\"" & id & "\" x=\"" & $x & "\" y=\"" & $y &
    "\" width=\"" & $w & "\" height=\"" & $h &
    "\" fill=\"none\" stroke=\"" & color & "\" stroke-width=\"1\"/>"

proc encodeAnnotatedSvg*(buf: ScreenBuffer; root: TerminalNode;
                        comp: Compositor; focusedId: int): string =
  ## Produce the annotated SVG. The base layer is `encodeSvg(buf)`; we
  ## strip the closing `</svg>` and inject overlay rects before
  ## re-emitting it.
  let base = svgMod.encodeSvg(buf)
  # Drop the final `</svg>\n` so we can append overlays.
  let close = "</svg>\n"
  var head = base
  if base.endsWith(close):
    head = base[0 ..< base.len - close.len]
  var lines: seq[string] = @[]
  lines.add head
  # Bounding-box overlay for every visible node (placeholder layout).
  let nodeIds = nodesInRenderOrder(root)
  for nid in nodeIds:
    let region = compositor.layoutRegionFor(comp, root, nid)
    if region.width == 0 or region.height == 0: continue
    lines.add rectStr("box-" & $nid, region.row, region.col,
                      region.width, region.height, "#3399ff")
  # Focus overlay.
  if focusedId != 0:
    let f = compositor.layoutRegionFor(comp, root, focusedId)
    if f.width > 0 and f.height > 0:
      lines.add rectStr("focus", f.row, f.col, f.width, f.height,
                        "#ff9900")
  # Dirty-region overlay — semi-transparent red.
  for region in comp.lastDirty:
    lines.add "  <rect id=\"dirty-" & $region.row & "-" & $region.col &
      "\" x=\"" & $(region.col * cellWidth) & "\" y=\"" &
      $(region.row * cellHeight) & "\" width=\"" &
      $(region.width * cellWidth) & "\" height=\"" & $cellHeight &
      "\" fill=\"#ff0000\" fill-opacity=\"0.2\"/>"
  lines.add "</svg>"
  result = lines.join("\n") & "\n"
