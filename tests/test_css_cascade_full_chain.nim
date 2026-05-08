## test_css_cascade_full_chain
##
## Cascade with three sources (default + user + inline) on a small
## DOM. Verify the computed style for a deeply-nested node integrates
## all three sources and that source priority + specificity break ties
## the right way.

import unittest
import isonim_tui

suite "M5: cascade full chain":
  test "test_cascade_full_chain":
    # Build a tree:
    # root#app .container > Container#body > Button#submit
    let r = TerminalRenderer()
    let root = r.createElement("Screen")
    r.setAttribute(root, "id", "app")
    r.setAttribute(root, "class", "container")
    let body = r.createElement("Container")
    r.setAttribute(body, "id", "body")
    r.appendChild(root, body)
    let btn = r.createElement("Button")
    r.setAttribute(btn, "id", "submit")
    r.setAttribute(btn, "class", "primary")
    r.appendChild(body, btn)

    # Three sources with progressively higher priority.
    let sheet = newStylesheet()

    # Default (lowest tier)
    sheet.addCss(ssDefault, "default", """
      Screen { background: black; color: white; }
      Button { width: 50%; height: 1; background: blue; color: white; }
    """)

    # User stylesheet (mid tier)
    sheet.addCss(ssUser, "app.tcss", """
      Container > Button { width: 100%; }
      Button.primary { background: red; }
    """)

    # Inline (highest tier) — bumps width to a fixed cell count
    sheet.addInlineDeclarations(btn.id, @[
      Declaration(name: "color", propertyKind: pkColor,
                  value: colorValue(namedCss("yellow")),
                  important: false),
    ])

    let ctx = NodeContext(node: btn, pseudo: {})
    let computed = computeStyles(sheet, ctx)
    # Cascade chain:
    #   width: 50% (Button) -> 100% (Container > Button) -> 100%
    check computed.width.unit == suPercent
    check computed.width.value == 100.0
    # background: blue -> red (.primary).
    check computed.background.kind == cckNamed
    check computed.background.name == "red"
    # color: white -> yellow (inline).
    check computed.color.kind == cckNamed
    check computed.color.name == "yellow"
    # height stays 1 (only set in default).
    check computed.height.unit == suCells
    check computed.height.value == 1.0

  test "test_cascade_specificity_ordering":
    let r = TerminalRenderer()
    let n = r.createElement("Button")
    r.setAttribute(n, "id", "submit")
    r.setAttribute(n, "class", "primary")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { width: 10; }
      .primary { width: 20; }
      #submit { width: 30; }
      Button.primary { width: 40; }
    """)
    let ctx = NodeContext(node: n, pseudo: {})
    let computed = computeStyles(sheet, ctx)
    # #id (1,0,0) beats Button.primary (0,1,1) beats .primary (0,1,0)
    # beats Button (0,0,1).
    check computed.width.unit == suCells
    check computed.width.value == 30.0

  test "test_cascade_important_wins":
    let r = TerminalRenderer()
    let n = r.createElement("Button")
    r.setAttribute(n, "id", "submit")
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { width: 10 !important; }
      #submit { width: 30; }
    """)
    let ctx = NodeContext(node: n, pseudo: {})
    let computed = computeStyles(sheet, ctx)
    # !important on the lower-specificity rule beats the unimportant one.
    check computed.width.value == 10.0
