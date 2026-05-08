## test_css_tailwind_compat
##
## The IsoNim Tailwind expansion (`isonim/dsl/tailwind.nim`) yields a
## `seq[(prop, val: string)]` that downstream renderers feed into
## `setStyle`. With M5 the same pairs need to flow through the cascade
## as inline declarations and produce the same computed values.
##
## We can't trigger the macro without the wider isonim DSL, but the
## compile-time expansion proc is callable directly. The fixture
## tailwind-styles.json in the sibling repo is currently empty; this
## test feeds a synthetic class -> property mapping mirroring what the
## CLI would emit, then runs both pipelines and checks they agree.

import unittest
import std/[strtabs, strutils, tables]
import isonim_tui
import isonim_tui/css/properties
import isonim_tui/css/parse

# Minimal in-test mapping: simulates the "bg-blue-500 p-4" -> property
# pairs that `isonim/dsl/tailwind.nim` produces from the JSON.
let tailwindClassMap = newStringTable({
  "bg-red": "background: red;",
  "p-1": "padding: 1;",
  "w-full": "width: 100%;",
  "text-bold": "text-style: bold;",
})

proc expandClasses(classes: string): seq[Declaration] =
  ## Mirrors `expandTailwindClasses` -> declarations. We re-use the
  ## real CSS parser to convert the `prop: val;` pairs, so we go
  ## through the *exact* code path the M5 cascade uses.
  var css = ""
  for cls in classes.split(' '):
    if cls in tailwindClassMap:
      css.add tailwindClassMap[cls]
      css.add " "
  let parsed = parseCss("* { " & css & " }", "tailwind-inline")
  if parsed.rules.len > 0: parsed.rules[0].declarations
  else: @[]

suite "M5: Tailwind compat":
  test "test_tailwind_compat":
    # An app using `class="bg-red p-1 w-full text-bold"` expands to four
    # declarations that go in via the inline source and produce the
    # same computed style as if the user had written them in TCSS.
    let r = TerminalRenderer()
    let n = r.createElement("Button")
    r.setAttribute(n, "class", "bg-red p-1 w-full text-bold")

    # Path 1: Tailwind expansion -> inline cascade
    let sheet1 = newStylesheet()
    let decls = expandClasses(n.attributes.getOrDefault("class", ""))
    sheet1.addInlineDeclarations(n.id, decls)
    let cs1 = computeStyles(sheet1, NodeContext(node: n, pseudo: {}))

    # Path 2: equivalent CSS through the regular cascade
    let sheet2 = newStylesheet()
    sheet2.addCss(ssUser, "equivalent.tcss",
                  "Button { background: red; padding: 1; width: 100%; text-style: bold; }")
    let cs2 = computeStyles(sheet2, NodeContext(node: n, pseudo: {}))

    # Same computed style produced by both paths.
    check cs1.background == cs2.background
    check cs1.padding.top == cs2.padding.top
    check cs1.padding.right == cs2.padding.right
    check cs1.width == cs2.width
    check cs1.textStyle == cs2.textStyle
    check tsBold in cs1.textStyle
    check cs1.background.kind == cckNamed
    check cs1.background.name == "red"

  test "test_tailwind_inline_priority":
    # Inline (tailwind) declarations should *win* against ordinary
    # user CSS at lower tier — this matches the existing behaviour of
    # `setStyle` (which is per-element and unconditional).
    let r = TerminalRenderer()
    let n = r.createElement("Button")
    r.setAttribute(n, "class", "bg-red")

    let sheet = newStylesheet()
    sheet.addCss(ssUser, "user.tcss", "Button { background: blue; }")
    let decls = expandClasses("bg-red")
    sheet.addInlineDeclarations(n.id, decls)

    let cs = computeStyles(sheet, NodeContext(node: n, pseudo: {}))
    check cs.background.kind == cckNamed
    check cs.background.name == "red"  # inline beats user
