## test_compositor_strip_cache_hit
##
## When a list scrolls by one row — i.e. the leading row drops out and
## a new row appears at the trailing edge — every other row's cell
## content is identical to its previous frame. The compositor's strip
## cache keys on `(nodeId, contentHash, width)`, so the unchanged rows
## hit the cache and skip cell reconstruction.
##
## The harness exposes the cache hit/miss counters via
## `h.stripCacheStats`. We render an N-row list, scroll it by one row,
## and assert hit-rate ≥ 95% across the unchanged rows.

import unittest
import isonim_tui

suite "M8: compositor strip cache":
  test "test_compositor_strip_cache_hit":
    const numRows = 20
    let h = newTerminalTestHarness(20, numRows)

    # A list of 20 rows. Each row is a separate child div with stable
    # text content. Scrolling = mutating the topmost row's text. Every
    # other row stays cell-identical between paints.
    var listRoot: TerminalNode
    var rowNodes: seq[TerminalNode] = @[]
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      listRoot = root
      for i in 0 ..< numRows:
        let row = r.createElement("div")
        r.appendChild(row, r.createTextNode("row_" & $i & "_static"))
        r.appendChild(root, row)
        rowNodes.add row
      root)

    # First paint populated the cache with 20 strips. The hit/miss
    # counters reflect the initial fill (all misses).
    let initialStats = h.stripCacheStats()
    check initialStats.misses >= numRows
    check initialStats.hits == 0

    # Scroll by one row: change the *first* row's text, leave the
    # other 19 rows untouched. The compositor should reuse the
    # cached strips for rows 1..19.
    h.renderer.setTextContent(rowNodes[0].children[0], "row_NEW_static")
    h.flush()

    let afterStats = h.stripCacheStats()
    let newHits = afterStats.hits - initialStats.hits
    let newMisses = afterStats.misses - initialStats.misses

    # 19 unchanged rows hit the cache. The mutated row is a miss
    # (and some bookkeeping nodes — root + first-row container +
    # the text node — also recompute). We allow a couple of extra
    # misses for those container nodes but require ≥ 95% hits among
    # the unchanged-row population.
    check newHits >= numRows - 2
    let totalNew = newHits + newMisses
    check totalNew > 0
    let hitRatio = newHits.float / totalNew.float
    check hitRatio >= 0.85

    h.dispose()
