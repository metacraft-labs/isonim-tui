## isonim_tui/css/parse.nim
##
## Parser for IsoNim's TCSS. Consumes the token stream from
## `tokenize.nim` and produces a list of `Rule`s (selector list +
## declarations) plus optional variable definitions and at-rules.
##
## Design choice: every value is parsed into a typed `PropertyValue`
## here. The cascade in `styles.nim` only sees typed inputs.
##
## Error recovery: on a malformed declaration we skip to the next `;`
## or `}` and continue. Selector parse errors abort the rule but the
## next rule still parses. This is enough for `test_error_recovery`.

import std/strutils
import ./tokenize
import ./properties

# ----------------------------------------------------------------------------
# AST types
# ----------------------------------------------------------------------------

type
  CombinatorKind* = enum
    ckDescendant   ## (whitespace) the default
    ckChild        ## `>`

  SelectorKind* = enum
    skType         ## `Button` or `*` (universal stored as type "*")
    skId           ## `#id`
    skClass        ## `.class`
    skUniversal    ## `*`
    skPseudo       ## `:focus` (always attached to the previous selector
                   ## via `pseudoClasses`)

  SelectorFilter* = object
    ## Extra ID / class match attached to a compound selector, e.g.
    ## `Button.primary#submit` produces a single `Selector(kind=skType,
    ## name="Button", filters=@[(skClass,"primary"), (skId,"submit")])`.
    kind*: SelectorKind
    name*: string

  Selector* = object
    ## A single selector "atom" — type, id, or class. Compound modifiers
    ## (e.g. `.primary` and `#submit` on `Button.primary#submit`) live
    ## in `filters`. Pseudo-classes are stored on the atom they qualify.
    kind*: SelectorKind
    name*: string
    filters*: seq[SelectorFilter]
    pseudoClasses*: seq[string]  ## e.g. @[":focus", ":disabled"]
    combinator*: CombinatorKind  ## relationship to the previous selector
    advance*: int                ## 0 for pseudo-only, 1 otherwise

  SelectorSet* = object
    ## A whitespace-separated chain of selectors that must all match
    ## in document order. e.g. `Screen .panel #title` is one set.
    selectors*: seq[Selector]

  Declaration* = object
    name*: string                  ## raw CSS property name (e.g. "background")
    propertyKind*: PropertyKind    ## resolved property kind
    value*: PropertyValue          ## typed value
    important*: bool               ## `!important`

  AtRuleKind* = enum
    arNone
    arDark
    arLight
    arMedia

  Rule* = object
    ## One CSS rule. The `selectorSets` list is the comma-separated
    ## groups: `.a, .b { ... }` produces two SelectorSets.
    selectorSets*: seq[SelectorSet]
    declarations*: seq[Declaration]
    atRule*: AtRuleKind
    atRuleArg*: string  ## payload for `@media (...)` or named theme
    sourceOrder*: int   ## insertion order — used for cascade tie-breaking
    sourceName*: string ## e.g. "default", "user", "inline" (set by stylesheet)

  Variable* = object
    name*: string
    rawValue*: string  ## variable values are kept as raw text and
                       ## resolved at cascade time.

  ParseResult* = object
    rules*: seq[Rule]
    variables*: seq[Variable]
    errors*: seq[string]

  ParseError* = object of CatchableError

# ----------------------------------------------------------------------------
# Parser state
# ----------------------------------------------------------------------------

type
  Parser = object
    tokens: seq[Token]
    pos: int
    sourceName: string
    sourceOrder: int
    errors: seq[string]
    recover: bool

proc peek(p: Parser; off = 0): Token =
  if p.pos + off < p.tokens.len: p.tokens[p.pos + off]
  else: Token(kind: tkEof)

proc advance(p: var Parser) =
  if p.pos < p.tokens.len: inc p.pos

# ----------------------------------------------------------------------------
# Selector parsing
# ----------------------------------------------------------------------------

proc parseSelectorSet(p: var Parser): SelectorSet =
  ## Parse a single SelectorSet (whitespace-separated chain). Stops at
  ## `,` (new selector) or `{` (declaration block start).
  ##
  ## Compound selectors (`Button.primary`) are folded into a single
  ## `Selector` atom whose `filters` carry the trailing `.primary` /
  ## `#id` modifiers. Adjacency is detected via the tokenizer's
  ## `adjacentToPrev` flag.
  var sel: Selector
  var hasCurrent = false
  var combinator = ckDescendant

  template flushCurrent() =
    if hasCurrent:
      sel.combinator = combinator
      sel.advance = 1
      result.selectors.add(sel)
      sel = Selector()
      hasCurrent = false
      combinator = ckDescendant

  while p.pos < p.tokens.len:
    let tok = peek(p)
    case tok.kind
    of tkSelectorStartType, tkSelectorType:
      flushCurrent()
      sel = Selector(kind: skType, name: tok.value)
      hasCurrent = true
      advance(p)
    of tkSelectorStartId, tkSelectorId:
      if hasCurrent and tok.adjacentToPrev:
        sel.filters.add(SelectorFilter(kind: skId, name: tok.value))
      else:
        flushCurrent()
        sel = Selector(kind: skId, name: tok.value)
        hasCurrent = true
      advance(p)
    of tkSelectorStartClass, tkSelectorClass:
      if hasCurrent and tok.adjacentToPrev:
        sel.filters.add(SelectorFilter(kind: skClass, name: tok.value))
      else:
        flushCurrent()
        sel = Selector(kind: skClass, name: tok.value)
        hasCurrent = true
      advance(p)
    of tkSelectorStartUniversal, tkSelectorUniversal:
      flushCurrent()
      sel = Selector(kind: skUniversal, name: "*")
      hasCurrent = true
      advance(p)
    of tkPseudoClass:
      if not hasCurrent:
        # Bare pseudo-class. Treat as `*:foo`.
        sel = Selector(kind: skUniversal, name: "*")
        hasCurrent = true
      sel.pseudoClasses.add(tok.value)
      advance(p)
    of tkCombinatorChild:
      flushCurrent()
      combinator = ckChild
      advance(p)
    of tkNewSelector, tkDeclarationSetStart:
      break
    of tkEof:
      break
    else:
      # Unexpected token in selector position. Skip if recovering.
      if p.recover:
        advance(p)
      else:
        raise newException(ParseError,
          "unexpected token " & $tok.kind & " in selector at " &
          $tok.line & ":" & $tok.col)
  flushCurrent()

# ----------------------------------------------------------------------------
# Value parsing
# ----------------------------------------------------------------------------

proc collectValueTokens(p: var Parser): tuple[tokens: seq[Token], important: bool] =
  ## Collect tokens until a `;` or `}` boundary. The first `}` closes
  ## the declaration block — the parser leaves it unconsumed for the
  ## block parser to pick up.
  var imp = false
  while p.pos < p.tokens.len:
    let tok = peek(p)
    case tok.kind
    of tkDeclarationEnd:
      advance(p)
      break
    of tkDeclarationSetEnd:
      # Don't consume the `}` — the rule parser handles it.
      break
    of tkEof:
      break
    of tkImportant:
      imp = true
      advance(p)
    else:
      result.tokens.add(tok)
      advance(p)
  result.important = imp

proc parseScalarToken(tok: Token): Scalar =
  case tok.kind
  of tkScalar, tkNumber:
    parseScalar(tok.value)
  of tkToken:
    if tok.value == "auto":
      autoScalar()
    else:
      raise newException(ParseError,
        "cannot parse scalar from token " & tok.value)
  else:
    raise newException(ParseError,
      "cannot parse scalar from token kind " & $tok.kind)

proc parseColorTokens(toks: seq[Token]): CssColor =
  if toks.len == 0:
    raise newException(ParseError, "empty color value")
  let first = toks[0]
  case first.kind
  of tkColorHex:
    parseHexColor(first.value)
  of tkColorFunc:
    parseRgbFunc(first.value)
  of tkToken:
    let v = first.value
    if v == "transparent":
      transparentCss()
    elif v.startsWith("ansi_"):
      ansiCss(v)
    else:
      let (found, _, _, _) = lookupNamed(v)
      if found: namedCss(v)
      else: namedCss(v)  ## still emit named — cascade may resolve via theme
  of tkVariableRef:
    varRefCss(first.value)
  else:
    raise newException(ParseError,
      "cannot parse color from token kind " & $first.kind)

proc parseEdgesTokens(toks: seq[Token]): Edges =
  ## Apply 1/2/3/4-value shorthand for margin/padding.
  var scalars: seq[Scalar]
  for tok in toks:
    if tok.kind == tkComma: continue
    scalars.add(parseScalarToken(tok))
  parseEdges(scalars)

proc parseTextStyleTokens(toks: seq[Token]): set[TextStyleFlag] =
  for tok in toks:
    if tok.kind != tkToken: continue
    let (found, flag) = parseTextStyleFlag(tok.value)
    if found: result.incl(flag)

proc parseEdgeBorderTokens(toks: seq[Token]): EdgeBorder =
  ## `border-top: solid red` — one keyword (style) and/or one colour.
  ## Either piece may be omitted; the cascade falls back to the
  ## non-edge border-style/border-color.
  for tok in toks:
    case tok.kind
    of tkToken:
      let (foundStyle, bs) = parseBorderStyle(tok.value)
      if foundStyle:
        result.style = bs
        result.styleSet = true
      else:
        # Treat unrecognised keyword as a named colour (e.g. `red`).
        result.color = namedCss(tok.value)
        result.colorSet = true
    of tkColorHex:
      result.color = parseHexColor(tok.value)
      result.colorSet = true
    of tkColorFunc:
      result.color = parseRgbFunc(tok.value)
      result.colorSet = true
    of tkVariableRef:
      result.color = varRefCss(tok.value)
      result.colorSet = true
    else:
      discard

proc parseSingleScalar(toks: seq[Token]): Scalar =
  if toks.len == 0:
    raise newException(ParseError, "empty length value")
  parseScalarToken(toks[0])

proc parseOffsetTokens(toks: seq[Token]): Offset =
  ## `offset: x y` — two scalars, separated by whitespace or a comma.
  var scalars: seq[Scalar]
  for tok in toks:
    if tok.kind == tkComma: continue
    scalars.add(parseScalarToken(tok))
  if scalars.len == 0:
    raise newException(ParseError, "offset requires at least one value")
  if scalars.len == 1:
    return Offset(x: scalars[0], y: scalars[0])
  Offset(x: scalars[0], y: scalars[1])

proc parseAlignPair(toks: seq[Token]): tuple[h: HAlignKind; v: VAlignKind] =
  ## `align: horizontal vertical` (e.g. `align: center middle`).
  var h: HAlignKind = haLeft
  var v: VAlignKind = vaTop
  var hSeen = false
  var vSeen = false
  for tok in toks:
    if tok.kind != tkToken: continue
    let (hOk, hk) = parseHAlign(tok.value)
    if hOk and not hSeen:
      h = hk; hSeen = true
      continue
    let (vOk, vk) = parseVAlign(tok.value)
    if vOk:
      v = vk; vSeen = true
  if not hSeen and not vSeen:
    raise newException(ParseError, "align requires horizontal+vertical keywords")
  (h: h, v: v)

proc parseLayerName(toks: seq[Token]): string =
  for tok in toks:
    if tok.kind in {tkToken, tkString}:
      var v = tok.value
      if v.len >= 2 and v[0] == '"' and v[^1] == '"':
        v = v[1 ..< v.len - 1]
      if v.len > 0:
        return v
  raise newException(ParseError, "layer expects an identifier")

proc parseLayerNames(toks: seq[Token]): seq[string] =
  for tok in toks:
    if tok.kind in {tkToken, tkString}:
      var v = tok.value
      if v.len >= 2 and v[0] == '"' and v[^1] == '"':
        v = v[1 ..< v.len - 1]
      if v.len > 0:
        result.add(v)
  if result.len == 0:
    raise newException(ParseError, "layers expects one or more identifiers")

proc parseGridSizeTokens(toks: seq[Token]): GridSize =
  ## Parse `grid-size <cols> [<rows>]`. Both values must be non-negative
  ## integers; if rows is omitted, the grid is unbounded vertically and
  ## we encode that as `rows == 0`.
  var ints: seq[int]
  for tok in toks:
    if tok.kind == tkComma: continue
    if tok.kind in {tkNumber, tkScalar}:
      try:
        let v = parseInt(tok.value)
        if v < 0:
          raise newException(ParseError,
            "grid-size requires non-negative integers")
        ints.add(v)
      except ValueError:
        raise newException(ParseError,
          "cannot parse grid-size integer: " & tok.value)
  if ints.len == 0:
    raise newException(ParseError, "grid-size requires at least <cols>")
  let cols = ints[0]
  let rows = if ints.len >= 2: ints[1] else: 0
  GridSize(cols: cols, rows: rows)

proc parseGridTracksTokens(toks: seq[Token]): seq[GridTrack] =
  ## Parse a `grid-rows` / `grid-columns` track list. Each track is one
  ## of: `auto`, `<n>`, `<n>fr`, `<n>%`. Whitespace separates tracks;
  ## commas are tolerated.
  for tok in toks:
    if tok.kind == tkComma: continue
    case tok.kind
    of tkToken:
      if tok.value == "auto":
        result.add(GridTrack(kind: gtkAuto, value: 1.0))
      else:
        raise newException(ParseError,
          "unknown grid track keyword: " & tok.value)
    of tkScalar:
      let v = tok.value
      if v.endsWith("fr"):
        try:
          let f = parseFloat(v[0 ..< v.len - 2])
          result.add(GridTrack(kind: gtkFr, value: f))
        except ValueError:
          raise newException(ParseError, "cannot parse fr track: " & v)
      elif v.endsWith("%"):
        try:
          let f = parseFloat(v[0 ..< v.len - 1])
          result.add(GridTrack(kind: gtkPercent, value: f))
        except ValueError:
          raise newException(ParseError, "cannot parse percent track: " & v)
      else:
        try:
          let f = parseFloat(v)
          result.add(GridTrack(kind: gtkFixed, value: f))
        except ValueError:
          raise newException(ParseError, "cannot parse track: " & v)
    of tkNumber:
      try:
        let f = parseFloat(tok.value)
        result.add(GridTrack(kind: gtkFixed, value: f))
      except ValueError:
        raise newException(ParseError,
          "cannot parse grid track: " & tok.value)
    else:
      discard
  if result.len == 0:
    raise newException(ParseError, "grid track list must not be empty")

proc parseGridGutterTokens(toks: seq[Token]): GridGutter =
  ## Parse `grid-gutter <horizontal> [<vertical>]`. Single value applies
  ## to both axes; the textual order is horizontal first then vertical
  ## (matches Textual's convention).
  var ints: seq[int]
  for tok in toks:
    if tok.kind == tkComma: continue
    if tok.kind in {tkNumber, tkScalar}:
      try:
        let v = parseInt(tok.value)
        if v < 0:
          raise newException(ParseError, "grid-gutter must be non-negative")
        ints.add(v)
      except ValueError:
        raise newException(ParseError,
          "cannot parse grid-gutter: " & tok.value)
  if ints.len == 0:
    raise newException(ParseError, "grid-gutter requires at least one value")
  let h = ints[0]
  let v = if ints.len >= 2: ints[1] else: ints[0]
  GridGutter(horizontal: h, vertical: v)

proc parseSmallInt(toks: seq[Token]): int =
  if toks.len == 0:
    raise newException(ParseError, "expected integer")
  case toks[0].kind
  of tkNumber, tkScalar:
    try:
      let v = parseInt(toks[0].value)
      if v < 0:
        raise newException(ParseError, "expected non-negative integer")
      return v
    except ValueError:
      raise newException(ParseError, "cannot parse integer: " & toks[0].value)
  else:
    raise newException(ParseError, "expected integer")

proc parseFloatLike(toks: seq[Token]): float64 =
  if toks.len == 0:
    raise newException(ParseError, "expected number")
  let tok = toks[0]
  case tok.kind
  of tkNumber:
    try:
      return parseFloat(tok.value)
    except ValueError:
      raise newException(ParseError, "cannot parse number: " & tok.value)
  of tkScalar:
    # Allow `opacity: 50%` to mean 0.5.
    if tok.value.endsWith("%"):
      try:
        return parseFloat(tok.value[0 ..< tok.value.len - 1]) / 100.0
      except ValueError:
        raise newException(ParseError, "cannot parse percent: " & tok.value)
    try:
      return parseFloat(tok.value)
    except ValueError:
      raise newException(ParseError, "cannot parse number: " & tok.value)
  else:
    raise newException(ParseError, "expected number")

proc parsePropertyValue*(prop: PropertyKind; toks: seq[Token]): PropertyValue =
  ## Convert a sequence of value tokens into a typed `PropertyValue`.
  ## Charter: every value lands in a typed enum / scalar — never a
  ## bare string.
  case prop
  of pkWidth, pkHeight, pkMinWidth, pkMinHeight, pkMaxWidth, pkMaxHeight:
    scalarValue(parseSingleScalar(toks))
  of pkMargin, pkPadding:
    edgesValue(parseEdgesTokens(toks))
  of pkMarginTop, pkMarginRight, pkMarginBottom, pkMarginLeft,
     pkPaddingTop, pkPaddingRight, pkPaddingBottom, pkPaddingLeft,
     pkOffsetX, pkOffsetY:
    scalarValue(parseSingleScalar(toks))
  of pkBackground, pkColor, pkBorderColor, pkTint,
     pkBorderTitleColor, pkBorderTitleBackground,
     pkBorderSubtitleColor, pkBorderSubtitleBackground,
     pkScrollbarColor, pkScrollbarBackground,
     pkLinkColor, pkLinkBackground:
    colorValue(parseColorTokens(toks))
  of pkBorderStyle:
    if toks.len == 0:
      raise newException(ParseError, "empty border-style value")
    if toks[0].kind != tkToken:
      raise newException(ParseError,
        "border-style must be a keyword, got " & $toks[0].kind)
    let (found, bs) = parseBorderStyle(toks[0].value)
    if not found:
      raise newException(ParseError,
        "unknown border style: " & toks[0].value)
    borderStyleValue(bs)
  of pkBorderTop, pkBorderRight, pkBorderBottom, pkBorderLeft:
    edgeBorderValue(parseEdgeBorderTokens(toks))
  of pkTextStyle, pkBorderTitleStyle, pkBorderSubtitleStyle, pkLinkStyle:
    textStyleValue(parseTextStyleTokens(toks))
  of pkTextAlign:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "text-align expects a keyword")
    let (found, a) = parseTextAlign(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown text-align: " & toks[0].value)
    textAlignValue(a)
  of pkBorderTitleAlign, pkBorderSubtitleAlign:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError,
        propertyKindName(prop) & " expects a keyword")
    let (found, h) = parseHAlign(toks[0].value)
    if not found:
      raise newException(ParseError,
        "unknown " & propertyKindName(prop) & ": " & toks[0].value)
    hAlignValue(h)
  of pkOpacity:
    numberValue(parseFloatLike(toks))
  of pkDisplay:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "display expects a keyword")
    let (found, d) = parseDisplay(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown display: " & toks[0].value)
    displayValue(d)
  of pkVisibility:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "visibility expects a keyword")
    let (found, v) = parseVisibility(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown visibility: " & toks[0].value)
    visibilityValue(v)
  of pkLayout:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "layout expects a keyword")
    let (found, l) = parseLayout(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown layout: " & toks[0].value)
    layoutValue(l)
  of pkDock:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "dock expects a keyword")
    let (found, d) = parseDock(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown dock: " & toks[0].value)
    dockValue(d)
  of pkOverflow, pkOverflowX, pkOverflowY:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "overflow expects a keyword")
    let (found, o) = parseOverflow(toks[0].value)
    if not found:
      raise newException(ParseError, "unknown overflow: " & toks[0].value)
    overflowValue(o)
  of pkOffset:
    offsetValue(parseOffsetTokens(toks))
  of pkAlign:
    let pair = parseAlignPair(toks)
    alignPairValue(pair.h, pair.v)
  of pkAlignHorizontal:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "align-horizontal expects a keyword")
    let (found, h) = parseHAlign(toks[0].value)
    if not found:
      raise newException(ParseError,
        "unknown align-horizontal: " & toks[0].value)
    hAlignValue(h)
  of pkAlignVertical:
    if toks.len == 0 or toks[0].kind != tkToken:
      raise newException(ParseError, "align-vertical expects a keyword")
    let (found, v) = parseVAlign(toks[0].value)
    if not found:
      raise newException(ParseError,
        "unknown align-vertical: " & toks[0].value)
    vAlignValue(v)
  of pkLayer:
    layerValue(parseLayerName(toks))
  of pkLayers:
    layersValue(parseLayerNames(toks))
  of pkScrollbarSize:
    # Either one int (uniform) or two ints (horizontal, vertical) —
    # mirrors Textual's `scrollbar-size: H V` shorthand.
    var ints: seq[int]
    for tok in toks:
      if tok.kind == tkComma: continue
      if tok.kind in {tkNumber, tkScalar}:
        try:
          let v = parseInt(tok.value)
          if v >= 0: ints.add(v)
        except ValueError:
          discard
    if ints.len == 0:
      raise newException(ParseError, "scrollbar-size expects integer(s)")
    # We carry the uniform value as a single int; the two-value form
    # is split by the cascade through the per-axis properties
    # `scrollbar-size-horizontal` / `scrollbar-size-vertical`. For the
    # shorthand we only use the first value here; widget code that
    # wants the asymmetric form should set the two axis properties
    # explicitly. (Textual's two-value form is rare in practice.)
    intValue(ints[0])
  of pkScrollbarSizeVertical, pkScrollbarSizeHorizontal:
    intValue(parseSmallInt(toks))
  of pkGridSize:
    gridSizeValue(parseGridSizeTokens(toks))
  of pkGridRows, pkGridColumns:
    gridTracksValue(parseGridTracksTokens(toks))
  of pkGridGutter:
    gridGutterValue(parseGridGutterTokens(toks))
  of pkColumnSpan, pkRowSpan:
    let v = parseSmallInt(toks)
    intValue(max(1, v))

# ----------------------------------------------------------------------------
# Declaration parsing
# ----------------------------------------------------------------------------

proc parseDeclaration(p: var Parser): tuple[ok: bool, decl: Declaration] =
  ## Parse one `name: value;` declaration. Caller has already verified
  ## the next token is `tkDeclarationName`.
  let nameTok = peek(p)
  if nameTok.kind != tkDeclarationName:
    return (false, Declaration())
  advance(p)
  let (foundProp, prop) = propertyKindFromName(nameTok.value)
  let valuePack = collectValueTokens(p)
  if not foundProp:
    # Unsupported property — record as error in recover mode, drop.
    p.errors.add("unsupported property '" & nameTok.value & "' at " &
                 $nameTok.line & ":" & $nameTok.col)
    return (false, Declaration())
  try:
    let value = parsePropertyValue(prop, valuePack.tokens)
    return (true, Declaration(
      name: nameTok.value,
      propertyKind: prop,
      value: value,
      important: valuePack.important))
  except ParseError as e:
    p.errors.add("parse error in '" & nameTok.value & "' at " &
                 $nameTok.line & ":" & $nameTok.col & ": " & e.msg)
    return (false, Declaration())

proc parseDeclarationBlock(p: var Parser): seq[Declaration] =
  ## Parse `{ decl; decl; ... }`. Caller already consumed the `{`.
  while p.pos < p.tokens.len:
    let tok = peek(p)
    case tok.kind
    of tkDeclarationSetEnd:
      advance(p)
      break
    of tkEof:
      break
    of tkDeclarationName:
      let (ok, decl) = parseDeclaration(p)
      if ok: result.add(decl)
    of tkDeclarationEnd:
      # stray semicolon
      advance(p)
    else:
      # Skip unknown tokens at declaration-block level (recovery).
      p.errors.add("unexpected token " & $tok.kind & " at " &
                   $tok.line & ":" & $tok.col)
      advance(p)

# ----------------------------------------------------------------------------
# Rule parsing
# ----------------------------------------------------------------------------

proc parseAtRule(p: var Parser; rule: var Rule) =
  ## We've consumed `@`; the at-rule name is in `peek(p)`. M5 used to
  ## eat tokens up to `{` here (the at-rule was treated as a flag with
  ## no selector). M6 needs the selector intact so `@dark Button { ... }`
  ## still applies to a `Button`. We just consume the at-rule keyword
  ## itself; the selector parser handles whatever follows.
  let nameTok = peek(p)
  if nameTok.kind != tkAtRule:
    return
  advance(p)
  case nameTok.value.toLowerAscii
  of "dark":
    rule.atRule = arDark
  of "light":
    rule.atRule = arLight
  of "media":
    rule.atRule = arMedia
    rule.atRuleArg = nameTok.value
    # `@media (...)` is parsed in M11; for now consume up to `{` so
    # the selector parser doesn't choke on the parenthesised expr.
    while p.pos < p.tokens.len and peek(p).kind != tkDeclarationSetStart and
          peek(p).kind != tkEof:
      advance(p)
  else:
    rule.atRule = arNone

proc parseRule(p: var Parser): tuple[ok: bool, rule: Rule] =
  var rule = Rule(sourceOrder: p.sourceOrder, sourceName: p.sourceName)
  inc p.sourceOrder

  # at-rule?
  if peek(p).kind == tkAtRule:
    parseAtRule(p, rule)

  # selector list, comma-separated
  while p.pos < p.tokens.len:
    let setStart = parseSelectorSet(p)
    if setStart.selectors.len > 0:
      rule.selectorSets.add(setStart)
    if peek(p).kind == tkNewSelector:
      advance(p)
      continue
    break

  if peek(p).kind != tkDeclarationSetStart:
    if rule.atRule == arNone and rule.selectorSets.len == 0:
      return (false, rule)
    # Selector or at-rule without `{` — error.
    p.errors.add("expected '{' after selector at " &
                 $peek(p).line & ":" & $peek(p).col)
    return (false, rule)
  advance(p)  # consume '{'
  rule.declarations = parseDeclarationBlock(p)
  return (true, rule)

# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

proc parseTokens*(tokens: seq[Token]; sourceName = "anon";
                  recover = true): ParseResult =
  ## Parse a token stream. Default `recover=true` matches Textual's
  ## error-recovery behaviour: a single bad rule doesn't kill the file.
  var p = Parser(
    tokens: tokens, pos: 0, sourceName: sourceName,
    sourceOrder: 0, recover: recover)
  while p.pos < p.tokens.len:
    let tok = peek(p)
    case tok.kind
    of tkEof:
      break
    of tkVariableName:
      # `$name` already produced as variable name; collect raw value
      # tokens.
      advance(p)
      var raw = ""
      while p.pos < p.tokens.len:
        let t2 = peek(p)
        if t2.kind == tkDeclarationEnd:
          advance(p); break
        if t2.kind == tkEof: break
        if raw.len > 0: raw.add(' ')
        raw.add(t2.value)
        advance(p)
      result.variables.add(Variable(name: tok.value, rawValue: raw))
    else:
      try:
        let (ok, rule) = parseRule(p)
        if ok:
          result.rules.add(rule)
      except ParseError as e:
        result.errors.add(e.msg)
        # Recovery: skip to next `}` or `;`
        while p.pos < p.tokens.len:
          let t2 = peek(p)
          if t2.kind == tkDeclarationSetEnd or t2.kind == tkEof:
            if t2.kind == tkDeclarationSetEnd: advance(p)
            break
          advance(p)
  result.errors.add(p.errors)

proc parseCss*(code: string; sourceName = "anon"): ParseResult =
  ## End-to-end: tokenize and parse a CSS string.
  let toks = tokenizeRecover(code)
  parseTokens(toks, sourceName, recover = true)
