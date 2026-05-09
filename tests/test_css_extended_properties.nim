## test_css_extended_properties
##
## M5-closure: real-stack tests for the property additions beyond the
## load-bearing 12. Every test runs real TCSS source through the real
## tokenizer / parser / cascade and asserts the typed computed-style
## value materialised on the `Styles` object.
##
## No mocks: a `TerminalRenderer` builds a small DOM, a real
## `Stylesheet` aggregates the rules, and the cascade is the same one
## widgets and the harness consume.

import unittest
import isonim_tui

template makeButton(): tuple[r: TerminalRenderer; n: TerminalNode] =
  let renderer = TerminalRenderer()
  let node = renderer.createElement("Button")
  renderer.setAttribute(node, "id", "submit")
  renderer.setAttribute(node, "class", "primary")
  (r: renderer, n: node)

suite "M5 closure: extended TCSS properties":

  test "test_per_edge_margin_padding":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        margin: 1 2;
        margin-top: 5;
        padding-left: 3;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    # The shorthand `margin: 1 2` expands to top=1, right=2, bottom=1,
    # left=2. `margin-top: 5` then overrides the top edge.
    check computed.margin.top.unit == suCells
    check computed.margin.top.value == 5.0
    check computed.margin.right.value == 2.0
    check computed.margin.bottom.value == 1.0
    check computed.margin.left.value == 2.0
    # `padding-left: 3` lands without a `padding` shorthand having
    # been provided — `setPaddingEdge` initialises the rest to zero.
    check computed.padding.left.unit == suCells
    check computed.padding.left.value == 3.0
    check computed.padding.top.value == 0.0
    check computed.padding.right.value == 0.0
    check computed.padding.bottom.value == 0.0

  test "test_per_edge_borders":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        border: solid;
        border-color: red;
        border-top: heavy blue;
        border-right: dashed;
        border-bottom: green;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.borderStyle == bsSolid
    check computed.borderColor.kind == cckNamed
    check computed.borderColor.name == "red"

    check computed.borderTopSet
    check computed.borderTop.styleSet
    check computed.borderTop.style == bsHeavy
    check computed.borderTop.colorSet
    check computed.borderTop.color.name == "blue"

    check computed.borderRightSet
    check computed.borderRight.styleSet
    check computed.borderRight.style == bsDashed
    check not computed.borderRight.colorSet

    check computed.borderBottomSet
    check not computed.borderBottom.styleSet
    check computed.borderBottom.colorSet
    check computed.borderBottom.color.name == "green"

    # border-left was not set; the cascade leaves the field default.
    check not computed.borderLeftSet

  test "test_overflow_axis_split":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { overflow: hidden; overflow-x: scroll; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.overflowYSet
    check computed.overflowY == ovHidden
    check computed.overflowXSet
    check computed.overflowX == ovScroll  # later override wins

  test "test_overflow_auto_default_propagates":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { overflow: auto; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.overflowX == ovAuto
    check computed.overflowY == ovAuto

  test "test_text_align_keywords":
    for (input, want) in [
      ("left", taLeft), ("center", taCenter), ("centre", taCenter),
      ("right", taRight), ("justify", taJustify),
      ("start", taStart), ("end", taEnd)]:
      let (_, n) = makeButton()
      let sheet = newStylesheet()
      sheet.addCss(ssUser, "x.tcss", "Button { text-align: " & input & "; }")
      let computed = computeStyles(sheet, NodeContext(node: n))
      check computed.textAlignSet
      check computed.textAlign == want

  test "test_offset_pair_and_axis":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { offset: 50% 2; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.offsetSet
    check computed.offset.x.unit == suPercent
    check computed.offset.x.value == 50.0
    check computed.offset.y.unit == suCells
    check computed.offset.y.value == 2.0

    let (_, n2) = makeButton()
    let sheet2 = newStylesheet()
    sheet2.addCss(ssUser, "app.tcss", """
      Button { offset-x: 4; offset-y: -3; }
    """)
    let c2 = computeStyles(sheet2, NodeContext(node: n2))
    check c2.offsetSet
    check c2.offset.x.value == 4.0
    check c2.offset.y.value == -3.0

  test "test_align_pair_and_axis":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { align: center middle; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.alignHorizontalSet
    check computed.alignHorizontal == haCenter
    check computed.alignVerticalSet
    check computed.alignVertical == vaMiddle

    let (_, n2) = makeButton()
    let sheet2 = newStylesheet()
    sheet2.addCss(ssUser, "app.tcss", """
      Button {
        align-horizontal: right;
        align-vertical: bottom;
      }
    """)
    let c2 = computeStyles(sheet2, NodeContext(node: n2))
    check c2.alignHorizontal == haRight
    check c2.alignVertical == vaBottom

  test "test_opacity_and_percent_form":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { opacity: 0.5; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.opacitySet
    check computed.opacity == 0.5

    let (_, n2) = makeButton()
    let sheet2 = newStylesheet()
    sheet2.addCss(ssUser, "app.tcss", """
      Button { opacity: 75%; }
    """)
    let c2 = computeStyles(sheet2, NodeContext(node: n2))
    check c2.opacity == 0.75

  test "test_tint_color":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button { tint: rgb(10, 20, 30); }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.tintSet
    check computed.tint.kind == cckRgb
    check computed.tint.r == 10u8
    check computed.tint.g == 20u8
    check computed.tint.b == 30u8

  test "test_layer_and_layers":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        layer: overlay;
        layers: base content overlay popup;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.layerSet
    check computed.layer == "overlay"
    check computed.layersSet
    check computed.layers == @["base", "content", "overlay", "popup"]

  test "test_scrollbar_size_and_colors":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        scrollbar-size: 2;
        scrollbar-size-vertical: 3;
        scrollbar-color: cyan;
        scrollbar-background: #102030;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    # `scrollbar-size: 2` sets both axes; the per-axis override
    # bumps vertical to 3.
    check computed.scrollbarSizeHorizontalSet
    check computed.scrollbarSizeHorizontal == 2
    check computed.scrollbarSizeVerticalSet
    check computed.scrollbarSizeVertical == 3
    check computed.scrollbarColorSet
    check computed.scrollbarColor.kind == cckNamed
    check computed.scrollbarColor.name == "cyan"
    check computed.scrollbarBackgroundSet
    check computed.scrollbarBackground.kind == cckRgb
    check computed.scrollbarBackground.r == 0x10u8
    check computed.scrollbarBackground.g == 0x20u8
    check computed.scrollbarBackground.b == 0x30u8

  test "test_link_styles":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        link-color: blue;
        link-background: white;
        link-style: bold underline;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.linkColorSet
    check computed.linkColor.name == "blue"
    check computed.linkBackgroundSet
    check computed.linkBackground.name == "white"
    check computed.linkStyleSet
    check tsBold in computed.linkStyle
    check tsUnderline in computed.linkStyle

  test "test_border_title_and_subtitle":
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssUser, "app.tcss", """
      Button {
        border-title-color: yellow;
        border-title-background: black;
        border-title-style: bold;
        border-title-align: center;
        border-subtitle-color: gray;
        border-subtitle-background: white;
        border-subtitle-style: italic;
        border-subtitle-align: right;
      }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    check computed.borderTitleColorSet
    check computed.borderTitleColor.name == "yellow"
    check computed.borderTitleBackgroundSet
    check computed.borderTitleBackground.name == "black"
    check computed.borderTitleStyleSet
    check tsBold in computed.borderTitleStyle
    check computed.borderTitleAlignSet
    check computed.borderTitleAlign == haCenter

    check computed.borderSubtitleColorSet
    check computed.borderSubtitleColor.name == "gray"
    check computed.borderSubtitleBackgroundSet
    check computed.borderSubtitleBackground.name == "white"
    check computed.borderSubtitleStyleSet
    check tsItalic in computed.borderSubtitleStyle
    check computed.borderSubtitleAlignSet
    check computed.borderSubtitleAlign == haRight

  test "test_extended_property_cascade_priority":
    # Closing the loop on the new properties: confirm they still
    # respect specificity, source-tier and !important like the core 12.
    let (_, n) = makeButton()
    let sheet = newStylesheet()
    sheet.addCss(ssDefault, "default", """
      Button { opacity: 0.2; offset: 0 0; }
    """)
    sheet.addCss(ssUser, "app.tcss", """
      Button.primary { opacity: 0.6; }
      #submit { offset: 5 6; }
      Button { opacity: 0.9 !important; }
    """)
    let computed = computeStyles(sheet, NodeContext(node: n))
    # !important on Button beats Button.primary's higher specificity.
    check computed.opacity == 0.9
    # #submit's specificity beats Button.
    check computed.offset.x.value == 5.0
    check computed.offset.y.value == 6.0

  test "test_default_styles_populates_extended":
    # `defaultStyles()` must populate the new properties so the
    # cache-invalidation equality test continues to find a stable
    # baseline.
    let d = defaultStyles()
    check d.opacity == 1.0
    check d.textAlign == taStart
    check d.overflowX == ovVisible
    check d.overflowY == ovVisible
    check d.alignHorizontal == haLeft
    check d.alignVertical == vaTop
    check d.offset.x.value == 0.0
    check d.offset.y.value == 0.0
    check d.scrollbarSizeVertical == 1
    check d.scrollbarSizeHorizontal == 1
    check tsUnderline in d.linkStyle
