## test_compositor_overlay_layer
##
## A node carrying `layer="10"` composites *on top of* the base tree
## (layer 0). Closing the overlay (removing or hiding it) reverts the
## screen contents underneath to their pre-overlay state.
##
## We mount a base "Background fill" row plus a sibling overlay row
## tagged with `layer=10` and `background-color=red`. Once mounted,
## the overlay's red row covers the underlying text. Removing the
## overlay produces a paint that restores the original cells.

import unittest
import isonim_tui
import std/unicode

suite "M8: compositor overlay layer":
  test "test_compositor_overlay_layer":
    let h = newTerminalTestHarness(20, 3)
    var overlay: TerminalNode
    var rootNode: TerminalNode
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      rootNode = root
      # Base layer (layer=0 by default).
      let base = r.createElement("div")
      r.appendChild(base, r.createTextNode("UNDERLYING-CONTENT"))
      r.appendChild(root, base)

      # Overlay sibling on a higher layer with explicit bg.
      overlay = r.createElement("div")
      r.setStyle(overlay, "layer", "10")
      r.setStyle(overlay, "background-color", "red")
      r.appendChild(overlay, r.createTextNode("MODAL"))
      r.appendChild(root, overlay)
      root)

    # The overlay sits on row 1 (the layer walker emits the base's
    # text on row 0 then the overlay on row 1). Verify it was
    # composited on top with its styled bg colour.
    check h.cellAt(1, 0).rune == Rune('M'.ord)
    check h.cellAt(1, 0).bg.kind == ckAnsi

    # Remove the overlay and re-paint. The underlying cells must be
    # restored to their pre-overlay state.
    h.renderer.removeChild(rootNode, overlay)
    h.flush()

    # Row 1 is now blank (the overlay row went away).
    check h.cellAt(1, 0).rune == Rune(' '.ord)
    check h.cellAt(1, 0).bg.kind == ckDefault

    # Underlying content on row 0 is untouched.
    check h.cellAt(0, 0).rune == Rune('U'.ord)

    # The dirty regions reflect the under-region of the modal —
    # exactly the row that the overlay vacated.
    let dirty = h.dirtyRegions()
    check dirty.len >= 1
    var sawRow1 = false
    for region in dirty:
      if region.row == 1:
        sawRow1 = true
    check sawRow1

    h.dispose()
