## test_css_parse_real_textual_corpus
##
## Parse the curated `.tcss` fixtures and verify:
##   - rule count matches what the source visibly contains
##   - selectors are decomposed into typed atoms (id/class/type/pseudo)
##   - declarations carry typed values (no string fall-through)

import unittest
import std/[os, strutils]
import isonim_tui

const fixtureDir = currentSourcePath().parentDir() / "fixtures" / "tcss"

suite "M5: CSS parser real-stack corpus":
  test "test_parse_real_textual_corpus":
    let calc = readFile(fixtureDir / "calculator.tcss")
    let parsed = parseCss(calc, "calculator.tcss")
    # `Screen`, `#calculator`, `Button`, `#numbers`, `#number-0` = 5 rules
    check parsed.rules.len == 5
    # `overflow` isn't in our M5 subset, so the declaration is reported
    # as an error and dropped — the rule still parses.
    check parsed.errors.len == 1
    check parsed.errors[0].contains("overflow")
    check parsed.rules[0].selectorSets.len == 1
    check parsed.rules[0].selectorSets[0].selectors.len == 1
    check parsed.rules[0].selectorSets[0].selectors[0].kind == skType
    check parsed.rules[0].selectorSets[0].selectors[0].name == "Screen"

    # `#calculator` rule
    check parsed.rules[1].selectorSets[0].selectors[0].kind == skId
    check parsed.rules[1].selectorSets[0].selectors[0].name == "calculator"

    # Find the Button rule and check its declarations are typed.
    var buttonRule: Rule
    for r in parsed.rules:
      if r.selectorSets.len > 0 and
         r.selectorSets[0].selectors.len == 1 and
         r.selectorSets[0].selectors[0].kind == skType and
         r.selectorSets[0].selectors[0].name == "Button":
        buttonRule = r
        break
    check buttonRule.declarations.len == 2
    var widthDecl: Declaration
    for d in buttonRule.declarations:
      if d.propertyKind == pkWidth: widthDecl = d
    check widthDecl.value.kind == vkScalar
    check widthDecl.value.scalarVal.unit == suPercent
    check widthDecl.value.scalarVal.value == 100.0

  test "test_parse_pseudo_classes":
    let buttons = readFile(fixtureDir / "buttons.tcss")
    let parsed = parseCss(buttons, "buttons.tcss")
    check parsed.rules.len >= 6

    # Count rules with pseudo-classes
    var pseudoRuleCount = 0
    for r in parsed.rules:
      for sset in r.selectorSets:
        for sel in sset.selectors:
          if sel.pseudoClasses.len > 0:
            inc pseudoRuleCount; break
        if pseudoRuleCount > 0: break
    check pseudoRuleCount >= 3  # :hover, :focus, :disabled

  test "test_parse_descendant_and_child":
    let dialog = readFile(fixtureDir / "dialog.tcss")
    let parsed = parseCss(dialog, "dialog.tcss")
    check parsed.rules.len >= 4

    # `Container > Button`
    var foundChild = false
    for r in parsed.rules:
      for sset in r.selectorSets:
        if sset.selectors.len == 2 and
           sset.selectors[1].combinator == ckChild:
          foundChild = true
    check foundChild

    # `#dialog .ok-button` (descendant)
    var foundDescendant = false
    for r in parsed.rules:
      for sset in r.selectorSets:
        if sset.selectors.len == 2 and
           sset.selectors[0].kind == skId and
           sset.selectors[1].kind == skClass and
           sset.selectors[1].combinator == ckDescendant:
          foundDescendant = true
    check foundDescendant

  test "test_parse_typed_color_values":
    let scrollable = readFile(fixtureDir / "scrollable.tcss")
    let parsed = parseCss(scrollable, "scrollable.tcss")
    check parsed.rules.len >= 3

    # Find a rule with a hex background and check the typed color
    var found = false
    for r in parsed.rules:
      for d in r.declarations:
        if d.propertyKind == pkBackground and
           d.value.kind == vkColor:
          if d.value.colorVal.kind == cckRgb:
            check d.value.colorVal.r > 0u8 or d.value.colorVal.g > 0u8 or
                  d.value.colorVal.b > 0u8
            found = true
    check found
