## test_compositor_tint_overlay
##
## An `overlay: tint` node re-colours the cells already composited under its
## rectangle — blending foreground and background toward a tint — and leaves
## every glyph where it was. It takes no row of the flow layout, it is z-ordered
## by `layer` (a label on a higher layer is drawn over it, untinted), and its
## colours are quantised to the depth the caller names, so a 256-colour or
## 16-colour terminal is never sent a colour it cannot show.
##
## An absolutely positioned label (`position: absolute; top; left`) is the
## companion: drawn at a cell, masking only its own width, above the tint.
##
## Real stack: the production `TerminalRenderer` and `Compositor` through the
## test harness (`newTerminalTestHarness`), reading the composited cells.

import std/[unicode, unittest]

import isonim_tui

const
  Cols = 20
  Rows = 4
  Tint = (90'u8, 157'u8, 212'u8)       # #5a9dd4
  Ground = (40'u8, 40'u8, 40'u8)       # #282828 — the theme's ground
  Ink = (243'u8, 243'u8, 243'u8)       # #f3f3f3 — the theme's text

proc textRow(r: TerminalRenderer; text: string; fg = ""; bg = ""): TerminalNode =
  result = r.createElement("div")
  let t = r.createTextNode(text)
  if fg.len > 0: r.setStyle(t, "color", fg)
  if bg.len > 0: r.setStyle(t, "background-color", bg)
  r.appendChild(result, t)

proc spec(top, left, width, height: int; depth = odTrueColor;
          reverse = false; layer = 5): OverlaySpec =
  OverlaySpec(top: top, left: left, width: width, height: height,
              color: rgbColor(Tint[0], Tint[1], Tint[2]), alpha: 0.4,
              reverse: reverse,
              baseFg: rgbColor(Ink[0], Ink[1], Ink[2]),
              baseBg: rgbColor(Ground[0], Ground[1], Ground[2]),
              depth: depth, layer: layer)

proc mountWith(overlays: seq[OverlaySpec];
               ghost = ""; ghostTop = 0; ghostLeft = 0):
    TerminalTestHarness =
  result = newTerminalTestHarness(Cols, Rows)
  result.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    r.appendChild(root, textRow(r, "alpha beta gamma", "#c0c0c0", "#101010"))
    r.appendChild(root, textRow(r, "default colours"))
    r.appendChild(root, textRow(r, "wide 世界 cells"))
    r.appendChild(root, textRow(r, "last row"))
    for o in overlays:
      r.appendChild(root, overlayNode(r, o))
    if ghost.len > 0:
      let label = r.createElement("div")
      r.setStyle(label, "position", "absolute")
      r.setStyle(label, "top", $ghostTop)
      r.setStyle(label, "left", $ghostLeft)
      r.setStyle(label, "layer", "7")
      r.setStyle(label, "reverse", "true")
      r.appendChild(label, r.createTextNode(ghost))
      r.appendChild(root, label)
    root)

suite "overlay: a tint over composited cells":

  test "the cells inside the rectangle are re-coloured, glyphs unchanged":
    let base = mountWith(@[])
    let h = mountWith(@[spec(0, 6, 4, 2)])
    for row in 0 ..< Rows:
      for col in 0 ..< Cols:
        let before = base.cellAt(row, col)
        let after = h.cellAt(row, col)
        check after.rune == before.rune
        check after.width == before.width
        let inside = row in 0 .. 1 and col in 6 .. 9
        if inside:
          check after.bg != before.bg
          check after.bg.kind == ckRgb
        else:
          check after.fg == before.fg
          check after.bg == before.bg
          check after.attrs == before.attrs

  test "the blend moves toward the tint by alpha, from the theme's base for a default colour":
    let h = mountWith(@[spec(0, 0, Cols, Rows)])
    # Row 0: an explicit #101010 background, 40% of the way to #5a9dd4.
    let explicitBg = h.cellAt(0, 0).bg
    check (explicitBg.r, explicitBg.g, explicitBg.b) ==
          blendRgb((16'u8, 16'u8, 16'u8), Tint, 0.4)
    # Row 1: the DEFAULT background blends from the theme's ground, not black.
    let defaultBg = h.cellAt(1, 0).bg
    check (defaultBg.r, defaultBg.g, defaultBg.b) == blendRgb(Ground, Tint, 0.4)
    # Foregrounds move half as far, so the text stays legible over the tint.
    let fg = h.cellAt(0, 0).fg
    check (fg.r, fg.g, fg.b) == blendRgb((192'u8, 192'u8, 192'u8), Tint, 0.2)

  test "no flow row is taken: the rows under and after the overlay are where they were":
    let base = mountWith(@[])
    let h = mountWith(@[spec(3, 0, 5, 1)])
    for col in 0 ..< Cols:
      check h.cellAt(3, col).rune == base.cellAt(3, col).rune

  test "a wide glyph is re-coloured whole, and stays a pair":
    let h = mountWith(@[spec(2, 6, 1, 1)])   # starts on the wide glyph's first cell
    check h.cellAt(2, 5).width == 2
    let lead = h.cellAt(2, 5)
    let ghost = h.cellAt(2, 6)
    check ghost.width == 0
    check lead.rune == "世".runeAt(0)
    # Column 6 is the ghost: the rectangle takes the whole glyph at column 5.
    check lead.bg.kind == ckRgb
    check ghost.bg == lead.bg

  test "an absolute label at a higher layer is drawn over the tint, untinted":
    let h = mountWith(@[spec(0, 0, Cols, Rows)], ghost = "[Drag]",
                      ghostTop = 1, ghostLeft = 3)
    check h.cellAt(1, 3).rune == Rune('['.ord)
    check h.cellAt(1, 8).rune == Rune(']'.ord)
    check attrReverse in h.cellAt(1, 4).attrs
    check h.cellAt(1, 4).bg.kind == ckDefault
    # The cells beside it are still tinted.
    check h.cellAt(1, 2).bg.kind == ckRgb
    check h.cellAt(1, 9).bg.kind == ckRgb

  test "a label BELOW the overlay's layer is tinted with the rest":
    var lowered = spec(0, 0, Cols, Rows, layer = 9)
    let h = mountWith(@[lowered], ghost = "[Drag]", ghostTop = 1, ghostLeft = 3)
    check h.cellAt(1, 4).rune == Rune('D'.ord)
    check h.cellAt(1, 4).bg.kind == ckRgb

  test "the depth quantises the blend: 256 and 16 colours, and monochrome reverses":
    let h256 = mountWith(@[spec(0, 0, 4, 1, depth = od256)])
    check h256.cellAt(0, 0).bg.kind == ckIndexed
    check h256.cellAt(0, 0).bg.indexed ==
          nearest256(blendRgb((16'u8, 16'u8, 16'u8), Tint, 0.4))
    let h16 = mountWith(@[spec(0, 0, 4, 1, depth = od16)])
    check h16.cellAt(0, 0).bg.kind == ckAnsi
    # A LIGHT TINT A COARSE PALETTE WOULD SWALLOW: 10% of the blue over
    # #101010 is still ANSI black, so the blend is strengthened until the
    # 16-colour cell visibly changes.
    var faint = spec(0, 0, 4, 1, depth = od16)
    faint.alpha = 0.1
    check nearestAnsi16(blendRgb((16'u8, 16'u8, 16'u8), Tint, 0.1)) == acBlack
    let hFaint = mountWith(@[faint])
    check hFaint.cellAt(0, 0).bg.kind == ckAnsi
    check hFaint.cellAt(0, 0).bg.ansi != acBlack
    let mono = mountWith(@[spec(0, 0, 4, 1, depth = odMono)])
    let base = mountWith(@[])
    check attrReverse in mono.cellAt(0, 0).attrs
    check mono.cellAt(0, 0).bg == base.cellAt(0, 0).bg
    check mono.cellAt(0, 0).fg == base.cellAt(0, 0).fg

  test "reverse is an addition to the blend when asked for":
    let h = mountWith(@[spec(0, 0, 4, 1, reverse = true)])
    check attrReverse in h.cellAt(0, 0).attrs
    check h.cellAt(0, 0).bg.kind == ckRgb
    check attrReverse notin h.cellAt(0, 5).attrs

  test "a node round-trips its spec":
    let r = TerminalRenderer()
    let s = spec(2, 3, 4, 5, depth = od256, reverse = true, layer = 6)
    let back = overlaySpecOf(overlayNode(r, s), 6)
    check back.top == 2 and back.left == 3 and back.width == 4 and
          back.height == 5
    check back.color == s.color and back.baseFg == s.baseFg and
          back.baseBg == s.baseBg
    check back.depth == od256 and back.reverse and back.layer == 6
    check abs(back.alpha - 0.4) < 1e-9
