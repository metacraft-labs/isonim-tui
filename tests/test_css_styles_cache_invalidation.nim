## test_css_styles_cache_invalidation
##
## Mutating the stylesheet bumps its revision; the cache lookup uses
## the new revision as part of its key, so old entries are skipped.
## A subsequent prune drops them.

import unittest
import std/[tables]
import isonim_tui

suite "M5: styles cache invalidation":
  test "test_styles_cache_invalidation":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "v1.tcss", "Button { background: blue; }")
    let cache = newStylesCache()

    # First lookup
    let key1 = StyleCacheKey(
      nodeId: btn.id, revision: sheet.revision, pseudo: {})
    let s1 = cache.lookup(key1, sheet, NodeContext(node: btn, pseudo: {}))
    check s1.background.name == "blue"
    check cache.stats.misses == 1
    check cache.stats.hits == 0

    # Hit on second lookup
    discard cache.lookup(key1, sheet, NodeContext(node: btn, pseudo: {}))
    check cache.stats.hits == 1

    # Mutate the stylesheet — revision bumps
    let oldRev = sheet.revision
    sheet.addCss(ssUser, "v2.tcss", "Button { background: red; }")
    check sheet.revision > oldRev

    # New revision -> new cache key -> miss -> recomputed style
    let key2 = StyleCacheKey(
      nodeId: btn.id, revision: sheet.revision, pseudo: {})
    let s2 = cache.lookup(key2, sheet, NodeContext(node: btn, pseudo: {}))
    check s2.background.name == "red"
    check cache.stats.misses == 2

    # Prune drops stale-revision entries
    let beforePrune = cache.entries.len
    cache.prune(sheet.revision)
    check cache.entries.len < beforePrune
    check cache.stats.invalidations >= 1

  test "test_invalidate_node_drops_only_that_nodes_entries":
    let r = TerminalRenderer()
    let a = r.createElement("Button"); r.setAttribute(a, "id", "a")
    let b = r.createElement("Button"); r.setAttribute(b, "id", "b")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "x.tcss", "Button { background: blue; } #a { background: red; }")
    let cache = newStylesCache()

    discard cache.lookup(
      StyleCacheKey(nodeId: a.id, revision: sheet.revision, pseudo: {}),
      sheet, NodeContext(node: a, pseudo: {}))
    discard cache.lookup(
      StyleCacheKey(nodeId: b.id, revision: sheet.revision, pseudo: {}),
      sheet, NodeContext(node: b, pseudo: {}))
    check cache.entries.len == 2

    cache.invalidateNode(a.id)
    check cache.entries.len == 1
