## isonim_tui/css/styles.nim
##
## The `Styles` object — typed, value-typed property storage. Mirrors
## Textual's `Styles` from `css/styles.py` but only for the
## load-bearing M5 subset (12 properties).
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
    background*: CssColor
    backgroundSet*: bool
    color*: CssColor
    colorSet*: bool
    textStyle*: set[TextStyleFlag]
    textStyleSet*: bool
    display*: DisplayKind
    displaySet*: bool
    visibility*: VisibilityKind
    visibilitySet*: bool
    layout*: LayoutKind
    layoutSet*: bool
    dock*: DockKind
    dockSet*: bool

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
  result.textStyle = {}
  result.display = dkBlock
  result.visibility = vkVisible
  result.layout = lkVertical
  result.dock = dockNone

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
  of pkPadding:
    if value.kind == vkEdges:
      s.padding = value.edgesVal; s.paddingSet = true
  of pkBorderStyle:
    if value.kind == vkBorderStyle:
      s.borderStyle = value.borderVal; s.borderStyleSet = true
  of pkBorderColor:
    if value.kind == vkColor:
      s.borderColor = value.colorVal; s.borderColorSet = true
  of pkBackground:
    if value.kind == vkColor:
      s.background = value.colorVal; s.backgroundSet = true
  of pkColor:
    if value.kind == vkColor:
      s.color = value.colorVal; s.colorSet = true
  of pkTextStyle:
    if value.kind == vkTextStyle:
      s.textStyle = value.textStyleVal; s.textStyleSet = true
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

# ----------------------------------------------------------------------------
# Equality (used by cache invalidation and tests)
# ----------------------------------------------------------------------------

proc `==`*(a, b: Styles): bool =
  ## Structural equality across the supported subset. Used by the
  ## cache-invalidation test to confirm a re-cascade either changed
  ## or didn't change the computed style.
  result = a.width == b.width and a.widthSet == b.widthSet and
    a.height == b.height and a.heightSet == b.heightSet and
    a.minWidth == b.minWidth and a.minWidthSet == b.minWidthSet and
    a.minHeight == b.minHeight and a.minHeightSet == b.minHeightSet and
    a.maxWidth == b.maxWidth and a.maxWidthSet == b.maxWidthSet and
    a.maxHeight == b.maxHeight and a.maxHeightSet == b.maxHeightSet and
    edgesEqual(a.margin, b.margin) and a.marginSet == b.marginSet and
    edgesEqual(a.padding, b.padding) and a.paddingSet == b.paddingSet and
    a.borderStyle == b.borderStyle and a.borderStyleSet == b.borderStyleSet and
    a.borderColor == b.borderColor and a.borderColorSet == b.borderColorSet and
    a.background == b.background and a.backgroundSet == b.backgroundSet and
    a.color == b.color and a.colorSet == b.colorSet and
    a.textStyle == b.textStyle and a.textStyleSet == b.textStyleSet and
    a.display == b.display and a.displaySet == b.displaySet and
    a.visibility == b.visibility and a.visibilitySet == b.visibilitySet and
    a.layout == b.layout and a.layoutSet == b.layoutSet and
    a.dock == b.dock and a.dockSet == b.dockSet
