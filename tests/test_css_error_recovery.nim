## test_css_error_recovery
##
## Malformed declarations are reported but don't kill the file —
## downstream rules still parse and apply.

import unittest
import std/[strutils]
import isonim_tui

suite "M5: CSS error recovery":
  test "test_error_recovery_malformed_value":
    let css = """
      Button { width: not-a-number; }
      Button { height: 10; }
    """
    let parsed = parseCss(css, "broken.tcss")
    # The first rule's malformed `width` is recorded as an error.
    check parsed.errors.len >= 1
    var hasWidthError = false
    for e in parsed.errors:
      if "width" in e: hasWidthError = true
    check hasWidthError
    # The second rule still applied: parsed has both rules.
    check parsed.rules.len == 2
    # And the second rule's height is correct.
    var found = false
    for r in parsed.rules:
      for d in r.declarations:
        if d.propertyKind == pkHeight and d.value.kind == vkScalar and
           d.value.scalarVal.value == 10.0:
          found = true
    check found

  test "test_error_recovery_unknown_property":
    let css = """
      Button { totally-unknown-prop: foo; width: 50%; }
    """
    let parsed = parseCss(css, "broken.tcss")
    check parsed.errors.len >= 1
    check parsed.rules.len == 1
    # The supported property still landed.
    var foundWidth = false
    for d in parsed.rules[0].declarations:
      if d.propertyKind == pkWidth: foundWidth = true
    check foundWidth

  test "test_error_recovery_continues_past_lex_glitch":
    let css = """
      Button { background: blue; }
      ?? not valid ?? { color: red; }
      Container { padding: 1; }
    """
    let parsed = parseCss(css, "messy.tcss")
    # First and third rules should parse; middle is best-effort.
    check parsed.rules.len >= 2
    var hasButton = false
    var hasContainer = false
    for r in parsed.rules:
      for sset in r.selectorSets:
        for s in sset.selectors:
          if s.kind == skType and s.name == "Button": hasButton = true
          if s.kind == skType and s.name == "Container": hasContainer = true
    check hasButton
    check hasContainer
