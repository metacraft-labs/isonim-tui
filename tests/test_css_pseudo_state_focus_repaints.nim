## test_css_pseudo_state_focus_repaints
##
## Pseudo-state plumbing: a focus transition produces a different
## computed style. The `:focus` rule overrides the default background.

import unittest
import isonim_tui

suite "M5: pseudo-state focus repaints":
  test "test_pseudo_state_focus_repaints":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    r.setAttribute(btn, "id", "submit")

    let sheet = newStylesheet()
    sheet.addCss(ssUser, "buttons.tcss", """
      Button { background: blue; color: white; }
      Button:focus { background: green; border: heavy; }
    """)

    # Without focus
    let unfocused = computeStyles(sheet, NodeContext(node: btn, pseudo: {}))
    check unfocused.background.kind == cckNamed
    check unfocused.background.name == "blue"
    check unfocused.borderStyle == bsNone

    # With focus
    let focused = computeStyles(sheet, NodeContext(
      node: btn, pseudo: {psFocus}))
    check focused.background.name == "green"
    check focused.borderStyle == bsHeavy

  test "test_pseudo_state_disabled_dimmed":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "buttons.tcss", """
      Button { color: white; }
      Button:disabled { color: gray; }
    """)
    let normal = computeStyles(sheet, NodeContext(node: btn, pseudo: {}))
    check normal.color.name == "white"
    let disabled = computeStyles(sheet, NodeContext(
      node: btn, pseudo: {psDisabled}))
    check disabled.color.name == "gray"

  test "test_pseudo_state_cache_changes_on_state_transition":
    let r = TerminalRenderer()
    let btn = r.createElement("Button")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "buttons.tcss", """
      Button { background: blue; }
      Button:focus { background: red; }
    """)
    let cache = newStylesCache()

    let key1 = StyleCacheKey(nodeId: btn.id, revision: sheet.revision,
                              pseudo: {})
    let s1 = cache.lookup(key1, sheet, NodeContext(node: btn, pseudo: {}))
    check s1.background.name == "blue"
    check cache.stats.misses == 1

    # Same key, second call: hit.
    let s1b = cache.lookup(key1, sheet, NodeContext(node: btn, pseudo: {}))
    check s1b.background.name == "blue"
    check cache.stats.hits == 1

    # Pseudo state transition produces a different cache key.
    let key2 = StyleCacheKey(nodeId: btn.id, revision: sheet.revision,
                              pseudo: {psFocus})
    let s2 = cache.lookup(key2, sheet, NodeContext(
      node: btn, pseudo: {psFocus}))
    check s2.background.name == "red"
    check cache.stats.misses == 2
