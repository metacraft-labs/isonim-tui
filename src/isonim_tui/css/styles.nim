## isonim_tui/css/styles.nim
##
## The `Styles` object — typed, value-typed property storage. Mirrors
## Textual's `Styles` from `css/styles.py`.
##
## Cascade: `merge` walks declarations in source order and stamps
## values into the typed fields. `!important` declarations always win
## over non-important ones; among equal-importance the higher specificity
## wins; ties broken by source order.
##
## "Computed style" derivation: for the M5 sub-stage, the computed
## style is just the cascade output. M6 layers theme variables and
## `:dark` / `:light` switching on top.

import ./properties

type
  Styles* = object
    ## Typed style bag. Each property has an `*Set` boolean so the
    ## cascade knows whether the field was actually set vs. left at
    ## the zero default. (Textual uses sentinel objects; Nim doesn't
    ## have those, so we use parallel boolean flags.)
    width*: Scalar
    widthSet*: bool
    height*: Scalar
    heightSet*: bool
    minWidth*: Scalar
    minWidthSet*: bool
    minHeight*: Scalar
    minHeightSet*: bool
    maxWidth*: Scalar
    maxWidthSet*: bool
    maxHeight*: Scalar
    maxHeightSet*: bool
    margin*: Edges
    marginSet*: bool
    padding*: Edges
    paddingSet*: bool
    borderStyle*: BorderStyle
    borderStyleSet*: bool
    borderColor*: CssColor
    borderColorSet*: bool
    # Per-edge border overrides (border-top / border-right / ...).
    # Each is an EdgeBorder which itself flags style/color presence.
    borderTop*: EdgeBorder
    borderTopSet*: bool
    borderRight*: EdgeBorder
    borderRightSet*: bool
    borderBottom*: EdgeBorder
    borderBottomSet*: bool
    borderLeft*: EdgeBorder
    borderLeftSet*: bool
    borderTitleColor*: CssColor
    borderTitleColorSet*: bool
    borderTitleBackground*: CssColor
    borderTitleBackgroundSet*: bool
    borderTitleStyle*: set[TextStyleFlag]
    borderTitleStyleSet*: bool
    borderTitleAlign*: HAlignKind
    borderTitleAlignSet*: bool
    borderSubtitleColor*: CssColor
    borderSubtitleColorSet*: bool
    borderSubtitleBackground*: CssColor
    borderSubtitleBackgroundSet*: bool
    borderSubtitleStyle*: set[TextStyleFlag]
    borderSubtitleStyleSet*: bool
    borderSubtitleAlign*: HAlignKind
    borderSubtitleAlignSet*: bool
    background*: CssColor
    backgroundSet*: bool
    color*: CssColor
    colorSet*: bool
    tint*: CssColor
    tintSet*: bool
    opacity*: float64
    opacitySet*: bool
    textStyle*: set[TextStyleFlag]
    textStyleSet*: bool
    textAlign*: TextAlignKind
    textAlignSet*: bool
    display*: DisplayKind
    displaySet*: bool
    visibility*: VisibilityKind
    visibilitySet*: bool
    layout*: LayoutKind
    layoutSet*: bool
    dock*: DockKind
    dockSet*: bool
    overflowX*: OverflowKind
    overflowXSet*: bool
    overflowY*: OverflowKind
    overflowYSet*: bool
    offset*: Offset
    offsetSet*: bool
    alignHorizontal*: HAlignKind
    alignHorizontalSet*: bool
    alignVertical*: VAlignKind
    alignVerticalSet*: bool
    layer*: string
    layerSet*: bool
    layers*: seq[string]
    layersSet*: bool
    scrollbarSizeVertical*: int
    scrollbarSizeVerticalSet*: bool
    scrollbarSizeHorizontal*: int
    scrollbarSizeHorizontalSet*: bool
    scrollbarColor*: CssColor
    scrollbarColorSet*: bool
    scrollbarBackground*: CssColor
    scrollbarBackgroundSet*: bool
    linkColor*: CssColor
    linkColorSet*: bool
    linkBackground*: CssColor
    linkBackgroundSet*: bool
    linkStyle*: set[TextStyleFlag]
    linkStyleSet*: bool

proc defaultStyles*(): Styles =
  ## The default per-property values that apply when no rule sets the
  ## property. Mirrors Textual's `_DEFAULT_STYLES` minus deferred
  ## properties.
  result.width = autoScalar()
  result.height = autoScalar()
  result.margin = edgesAll(cellsScalar(0))
  result.padding = edgesAll(cellsScalar(0))
  result.borderStyle = bsNone
  result.background = transparentCss()
  result.color = CssColor(kind: cckCurrent)
  result.tint = transparentCss()
  result.opacity = 1.0
  result.textStyle = {}
  result.textAlign = taStart
  result.display = dkBlock
  result.visibility = vkVisible
  result.layout = lkVertical
  result.dock = dockNone
  result.overflowX = ovVisible
  result.overflowY = ovVisible
  result.offset = Offset(x: cellsScalar(0), y: cellsScalar(0))
  result.alignHorizontal = haLeft
  result.alignVertical = vaTop
  # Textual default scrollbar size is 1 cell wide on each axis.
  result.scrollbarSizeVertical = 1
  result.scrollbarSizeHorizontal = 1
  result.scrollbarColor = CssColor(kind: cckCurrent)
  result.scrollbarBackground = CssColor(kind: cckCurrent)
  result.borderTitleColor = CssColor(kind: cckCurrent)
  result.borderTitleBackground = transparentCss()
  result.borderTitleStyle = {}
  result.borderTitleAlign = haLeft
  result.borderSubtitleColor = CssColor(kind: cckCurrent)
  result.borderSubtitleBackground = transparentCss()
  result.borderSubtitleStyle = {}
  result.borderSubtitleAlign = haRight
  result.linkColor = CssColor(kind: cckCurrent)
  result.linkBackground = transparentCss()
  result.linkStyle = {tsUnderline}

# ----------------------------------------------------------------------------
# Helpers for per-edge spacing
# ----------------------------------------------------------------------------

proc setMarginEdge(s: var Styles; which: PropertyKind; v: Scalar) =
  if not s.marginSet:
    s.margin = edgesAll(cellsScalar(0))
  case which
  of pkMarginTop:    s.margin.top = v
  of pkMarginRight:  s.margin.right = v
  of pkMarginBottom: s.margin.bottom = v
  of pkMarginLeft:   s.margin.left = v
  else: discard
  s.marginSet = true

proc setPaddingEdge(s: var Styles; which: PropertyKind; v: Scalar) =
  if not s.paddingSet:
    s.padding = edgesAll(cellsScalar(0))
  case which
  of pkPaddingTop:    s.padding.top = v
  of pkPaddingRight:  s.padding.right = v
  of pkPaddingBottom: s.padding.bottom = v
  of pkPaddingLeft:   s.padding.left = v
  else: discard
  s.paddingSet = true

# ----------------------------------------------------------------------------
# Apply a single declaration (used by cascade merging)
# ----------------------------------------------------------------------------

proc applyValue*(s: var Styles; prop: PropertyKind; value: PropertyValue) =
  ## Stamp a typed value into the right field. Switch is exhaustive
  ## for the supported PropertyKinds.
  case prop
  of pkWidth:
    if value.kind == vkScalar:
      s.width = value.scalarVal; s.widthSet = true
  of pkHeight:
    if value.kind == vkScalar:
      s.height = value.scalarVal; s.heightSet = true
  of pkMinWidth:
    if value.kind == vkScalar:
      s.minWidth = value.scalarVal; s.minWidthSet = true
  of pkMinHeight:
    if value.kind == vkScalar:
      s.minHeight = value.scalarVal; s.minHeightSet = true
  of pkMaxWidth:
    if value.kind == vkScalar:
      s.maxWidth = value.scalarVal; s.maxWidthSet = true
  of pkMaxHeight:
    if value.kind == vkScalar:
      s.maxHeight = value.scalarVal; s.maxHeightSet = true
  of pkMargin:
    if value.kind == vkEdges:
      s.margin = value.edgesVal; s.marginSet = true
  of pkMarginTop, pkMarginRight, pkMarginBottom, pkMarginLeft:
    if value.kind == vkScalar:
      setMarginEdge(s, prop, value.scalarVal)
  of pkPadding:
    if value.kind == vkEdges:
      s.padding = value.edgesVal; s.paddingSet = true
  of pkPaddingTop, pkPaddingRight, pkPaddingBottom, pkPaddingLeft:
    if value.kind == vkScalar:
      setPaddingEdge(s, prop, value.scalarVal)
  of pkBorderStyle:
    if value.kind == vkBorderStyle:
      s.borderStyle = value.borderVal; s.borderStyleSet = true
  of pkBorderColor:
    if value.kind == vkColor:
      s.borderColor = value.colorVal; s.borderColorSet = true
  of pkBorderTop:
    if value.kind == vkEdgeBorder:
      s.borderTop = value.edgeBorderVal; s.borderTopSet = true
  of pkBorderRight:
    if value.kind == vkEdgeBorder:
      s.borderRight = value.edgeBorderVal; s.borderRightSet = true
  of pkBorderBottom:
    if value.kind == vkEdgeBorder:
      s.borderBottom = value.edgeBorderVal; s.borderBottomSet = true
  of pkBorderLeft:
    if value.kind == vkEdgeBorder:
      s.borderLeft = value.edgeBorderVal; s.borderLeftSet = true
  of pkBorderTitleColor:
    if value.kind == vkColor:
      s.borderTitleColor = value.colorVal; s.borderTitleColorSet = true
  of pkBorderTitleBackground:
    if value.kind == vkColor:
      s.borderTitleBackground = value.colorVal; s.borderTitleBackgroundSet = true
  of pkBorderTitleStyle:
    if value.kind == vkTextStyle:
      s.borderTitleStyle = value.textStyleVal; s.borderTitleStyleSet = true
  of pkBorderTitleAlign:
    if value.kind == vkHAlign:
      s.borderTitleAlign = value.hAlignVal; s.borderTitleAlignSet = true
  of pkBorderSubtitleColor:
    if value.kind == vkColor:
      s.borderSubtitleColor = value.colorVal; s.borderSubtitleColorSet = true
  of pkBorderSubtitleBackground:
    if value.kind == vkColor:
      s.borderSubtitleBackground = value.colorVal
      s.borderSubtitleBackgroundSet = true
  of pkBorderSubtitleStyle:
    if value.kind == vkTextStyle:
      s.borderSubtitleStyle = value.textStyleVal; s.borderSubtitleStyleSet = true
  of pkBorderSubtitleAlign:
    if value.kind == vkHAlign:
      s.borderSubtitleAlign = value.hAlignVal; s.borderSubtitleAlignSet = true
  of pkBackground:
    if value.kind == vkColor:
      s.background = value.colorVal; s.backgroundSet = true
  of pkColor:
    if value.kind == vkColor:
      s.color = value.colorVal; s.colorSet = true
  of pkTint:
    if value.kind == vkColor:
      s.tint = value.colorVal; s.tintSet = true
  of pkOpacity:
    if value.kind == vkNumber:
      s.opacity = value.numberVal; s.opacitySet = true
  of pkTextStyle:
    if value.kind == vkTextStyle:
      s.textStyle = value.textStyleVal; s.textStyleSet = true
  of pkTextAlign:
    if value.kind == vkTextAlign:
      s.textAlign = value.textAlignVal; s.textAlignSet = true
  of pkDisplay:
    if value.kind == vkDisplay:
      s.display = value.displayVal; s.displaySet = true
  of pkVisibility:
    if value.kind == vkVisibility:
      s.visibility = value.visibilityVal; s.visibilitySet = true
  of pkLayout:
    if value.kind == vkLayout:
      s.layout = value.layoutVal; s.layoutSet = true
  of pkDock:
    if value.kind == vkDock:
      s.dock = value.dockVal; s.dockSet = true
  of pkOverflow:
    if value.kind == vkOverflow:
      s.overflowX = value.overflowVal; s.overflowXSet = true
      s.overflowY = value.overflowVal; s.overflowYSet = true
  of pkOverflowX:
    if value.kind == vkOverflow:
      s.overflowX = value.overflowVal; s.overflowXSet = true
  of pkOverflowY:
    if value.kind == vkOverflow:
      s.overflowY = value.overflowVal; s.overflowYSet = true
  of pkOffset:
    if value.kind == vkOffset:
      s.offset = value.offsetVal; s.offsetSet = true
  of pkOffsetX:
    if value.kind == vkScalar:
      if not s.offsetSet:
        s.offset = Offset(x: cellsScalar(0), y: cellsScalar(0))
      s.offset.x = value.scalarVal
      s.offsetSet = true
  of pkOffsetY:
    if value.kind == vkScalar:
      if not s.offsetSet:
        s.offset = Offset(x: cellsScalar(0), y: cellsScalar(0))
      s.offset.y = value.scalarVal
      s.offsetSet = true
  of pkAlign:
    if value.kind == vkAlignPair:
      s.alignHorizontal = value.hAlignPairVal; s.alignHorizontalSet = true
      s.alignVertical = value.vAlignPairVal; s.alignVerticalSet = true
  of pkAlignHorizontal:
    if value.kind == vkHAlign:
      s.alignHorizontal = value.hAlignVal; s.alignHorizontalSet = true
  of pkAlignVertical:
    if value.kind == vkVAlign:
      s.alignVertical = value.vAlignVal; s.alignVerticalSet = true
  of pkLayer:
    if value.kind == vkLayer:
      s.layer = value.layerVal; s.layerSet = true
  of pkLayers:
    if value.kind == vkLayers:
      s.layers = value.layersVal; s.layersSet = true
  of pkScrollbarSize:
    if value.kind == vkInt:
      s.scrollbarSizeVertical = value.intVal
      s.scrollbarSizeHorizontal = value.intVal
      s.scrollbarSizeVerticalSet = true
      s.scrollbarSizeHorizontalSet = true
  of pkScrollbarSizeVertical:
    if value.kind == vkInt:
      s.scrollbarSizeVertical = value.intVal
      s.scrollbarSizeVerticalSet = true
  of pkScrollbarSizeHorizontal:
    if value.kind == vkInt:
      s.scrollbarSizeHorizontal = value.intVal
      s.scrollbarSizeHorizontalSet = true
  of pkScrollbarColor:
    if value.kind == vkColor:
      s.scrollbarColor = value.colorVal; s.scrollbarColorSet = true
  of pkScrollbarBackground:
    if value.kind == vkColor:
      s.scrollbarBackground = value.colorVal; s.scrollbarBackgroundSet = true
  of pkLinkColor:
    if value.kind == vkColor:
      s.linkColor = value.colorVal; s.linkColorSet = true
  of pkLinkBackground:
    if value.kind == vkColor:
      s.linkBackground = value.colorVal; s.linkBackgroundSet = true
  of pkLinkStyle:
    if value.kind == vkTextStyle:
      s.linkStyle = value.textStyleVal; s.linkStyleSet = true

# ----------------------------------------------------------------------------
# Equality (used by cache invalidation and tests)
# ----------------------------------------------------------------------------

proc edgeBorderEqual(a, b: EdgeBorder): bool {.inline.} =
  a.style == b.style and a.styleSet == b.styleSet and
    a.color == b.color and a.colorSet == b.colorSet

proc offsetEqual(a, b: Offset): bool {.inline.} =
  a.x == b.x and a.y == b.y

proc `==`*(a, b: Styles): bool =
  ## Structural equality. Used by the cache-invalidation test to
  ## confirm a re-cascade either changed or didn't change the computed
  ## style.
  result =
    a.width == b.width and a.widthSet == b.widthSet and
    a.height == b.height and a.heightSet == b.heightSet and
    a.minWidth == b.minWidth and a.minWidthSet == b.minWidthSet and
    a.minHeight == b.minHeight and a.minHeightSet == b.minHeightSet and
    a.maxWidth == b.maxWidth and a.maxWidthSet == b.maxWidthSet and
    a.maxHeight == b.maxHeight and a.maxHeightSet == b.maxHeightSet and
    edgesEqual(a.margin, b.margin) and a.marginSet == b.marginSet and
    edgesEqual(a.padding, b.padding) and a.paddingSet == b.paddingSet and
    a.borderStyle == b.borderStyle and a.borderStyleSet == b.borderStyleSet and
    a.borderColor == b.borderColor and a.borderColorSet == b.borderColorSet and
    edgeBorderEqual(a.borderTop, b.borderTop) and
      a.borderTopSet == b.borderTopSet and
    edgeBorderEqual(a.borderRight, b.borderRight) and
      a.borderRightSet == b.borderRightSet and
    edgeBorderEqual(a.borderBottom, b.borderBottom) and
      a.borderBottomSet == b.borderBottomSet and
    edgeBorderEqual(a.borderLeft, b.borderLeft) and
      a.borderLeftSet == b.borderLeftSet and
    a.borderTitleColor == b.borderTitleColor and
      a.borderTitleColorSet == b.borderTitleColorSet and
    a.borderTitleBackground == b.borderTitleBackground and
      a.borderTitleBackgroundSet == b.borderTitleBackgroundSet and
    a.borderTitleStyle == b.borderTitleStyle and
      a.borderTitleStyleSet == b.borderTitleStyleSet and
    a.borderTitleAlign == b.borderTitleAlign and
      a.borderTitleAlignSet == b.borderTitleAlignSet and
    a.borderSubtitleColor == b.borderSubtitleColor and
      a.borderSubtitleColorSet == b.borderSubtitleColorSet and
    a.borderSubtitleBackground == b.borderSubtitleBackground and
      a.borderSubtitleBackgroundSet == b.borderSubtitleBackgroundSet and
    a.borderSubtitleStyle == b.borderSubtitleStyle and
      a.borderSubtitleStyleSet == b.borderSubtitleStyleSet and
    a.borderSubtitleAlign == b.borderSubtitleAlign and
      a.borderSubtitleAlignSet == b.borderSubtitleAlignSet and
    a.background == b.background and a.backgroundSet == b.backgroundSet and
    a.color == b.color and a.colorSet == b.colorSet and
    a.tint == b.tint and a.tintSet == b.tintSet and
    a.opacity == b.opacity and a.opacitySet == b.opacitySet and
    a.textStyle == b.textStyle and a.textStyleSet == b.textStyleSet and
    a.textAlign == b.textAlign and a.textAlignSet == b.textAlignSet and
    a.display == b.display and a.displaySet == b.displaySet and
    a.visibility == b.visibility and a.visibilitySet == b.visibilitySet and
    a.layout == b.layout and a.layoutSet == b.layoutSet and
    a.dock == b.dock and a.dockSet == b.dockSet and
    a.overflowX == b.overflowX and a.overflowXSet == b.overflowXSet and
    a.overflowY == b.overflowY and a.overflowYSet == b.overflowYSet and
    offsetEqual(a.offset, b.offset) and a.offsetSet == b.offsetSet and
    a.alignHorizontal == b.alignHorizontal and
      a.alignHorizontalSet == b.alignHorizontalSet and
    a.alignVertical == b.alignVertical and
      a.alignVerticalSet == b.alignVerticalSet and
    a.layer == b.layer and a.layerSet == b.layerSet and
    a.layers == b.layers and a.layersSet == b.layersSet and
    a.scrollbarSizeVertical == b.scrollbarSizeVertical and
      a.scrollbarSizeVerticalSet == b.scrollbarSizeVerticalSet and
    a.scrollbarSizeHorizontal == b.scrollbarSizeHorizontal and
      a.scrollbarSizeHorizontalSet == b.scrollbarSizeHorizontalSet and
    a.scrollbarColor == b.scrollbarColor and
      a.scrollbarColorSet == b.scrollbarColorSet and
    a.scrollbarBackground == b.scrollbarBackground and
      a.scrollbarBackgroundSet == b.scrollbarBackgroundSet and
    a.linkColor == b.linkColor and a.linkColorSet == b.linkColorSet and
    a.linkBackground == b.linkBackground and
      a.linkBackgroundSet == b.linkBackgroundSet and
    a.linkStyle == b.linkStyle and a.linkStyleSet == b.linkStyleSet
