## test_css_match_specificity_corpus
##
## Smaller subset of the (selector, DOM, expected-match) corpus.
## ~30 cases covering type / id / class / universal / pseudo /
## descendant / child / compound / combined.

import unittest
import isonim_tui

type
  Case = tuple
    css: string
    expected: bool

# Helper: build a tree (Screen > Container#main > Button.primary#submit)
# and run the matcher against `Button#submit`.
proc runCase(c: Case): bool =
  let r = TerminalRenderer()
  let screen = r.createElement("Screen")
  let container = r.createElement("Container")
  r.setAttribute(container, "id", "main")
  r.setAttribute(container, "class", "panel container")
  r.appendChild(screen, container)
  let btn = r.createElement("Button")
  r.setAttribute(btn, "id", "submit")
  r.setAttribute(btn, "class", "primary big")
  r.appendChild(container, btn)

  let parsed = parseCss(c.css & " { width: 1; }", "case.tcss")
  if parsed.rules.len == 0: return false
  let ctx = NodeContext(node: btn, pseudo: {psFocus, psHover})
  let (matched, _) = anySelectorMatches(parsed.rules[0], ctx)
  matched

let cases: seq[Case] = @[
  ("Button",                  true),
  ("Container",               false),
  ("Screen",                  false),
  ("#submit",                 true),
  ("#wrong",                  false),
  (".primary",                true),
  (".big",                    true),
  (".missing",                false),
  ("*",                       true),
  ("Button#submit",           true),
  ("Button#wrong",            false),
  ("Button.primary",          true),
  ("Button.primary.big",      true),
  ("Button.primary.missing",  false),
  (".primary.big",            true),
  ("Container Button",        true),
  ("Screen Button",           true),
  ("Screen Container Button", true),
  ("Container > Button",      true),
  ("Screen > Button",         false),
  ("Screen > Container > Button", true),
  ("Container .primary",      true),
  ("#main .primary",          true),
  ("#main #submit",           true),
  ("Button:focus",            true),
  ("Button:hover",            true),
  ("Button:disabled",         false),
  (":focus",                  true),
  ("Button.primary:focus",    true),
  ("Button.missing:focus",    false),
]

suite "M5: matcher specificity corpus":
  test "test_match_specificity_corpus_subset":
    var failures: seq[string]
    for i, c in cases:
      let got = runCase(c)
      if got != c.expected:
        failures.add("[" & $i & "] '" & c.css & "' expected=" &
                     $c.expected & " got=" & $got)
    check failures.len == 0
    if failures.len > 0:
      for f in failures: echo f

  test "test_specificity_ordering_id_beats_class":
    let r = TerminalRenderer()
    let n = r.createElement("Button")
    r.setAttribute(n, "id", "x"); r.setAttribute(n, "class", "y")
    let p1 = parseCss("#x { width: 10; }", "p1.tcss")
    let p2 = parseCss(".y { width: 20; }", "p2.tcss")
    let s1 = selectorSpecificity(p1.rules[0].selectorSets[0])
    let s2 = selectorSpecificity(p2.rules[0].selectorSets[0])
    # id specificity (1,0,0) > class specificity (0,1,0)
    check s1.ids == 1 and s1.classes == 0
    check s2.ids == 0 and s2.classes == 1
    check cmp(s1, s2) > 0
