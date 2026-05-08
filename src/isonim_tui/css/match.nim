## isonim_tui/css/match.nim
##
## Selector matcher. Given a `Selector` chain and a `TerminalNode`,
## decides whether the node matches.
##
## Supports:
##   - type (`Button`, `Screen`) — matched against `node.tag` and tag→kind
##     mapping
##   - id (`#id`) — matched against `node.attributes["id"]`
##   - class (`.class`) — matched against `node.attributes["class"]`
##     (space-separated)
##   - universal (`*`) — always matches
##   - pseudo-class (`:focus`, `:hover`, `:disabled`, `:dark`, `:light`)
##     — matched against the pseudo-state set carried alongside the node
##   - descendant (whitespace) — node's ancestor chain
##   - child (`>`) — node's immediate parent
##
## Specificity: computed Textual-style as `(id, class+pseudo, type)`
## triple, with `!important` adding a separate priority bit handled by
## the cascade.

import std/[strutils, sets, tables]
import ../renderer
import ./parse

type
  PseudoState* = enum
    psFocus
    psHover
    psDisabled
    psDark
    psLight

  Specificity* = object
    ## Specificity triple — higher tuples beat lower ones in the cascade.
    ids*: int
    classes*: int
    types*: int

  NodeContext* = object
    ## Wraps a TerminalNode plus its pseudo-state set, since pseudo-
    ## states are not stored on the TerminalNode itself (the renderer
    ## doesn't know about CSS).
    node*: TerminalNode
    pseudo*: set[PseudoState]

proc cmp*(a, b: Specificity): int =
  ## Three-tier comparison: ids beat classes beat types.
  if a.ids != b.ids: return cmp(a.ids, b.ids)
  if a.classes != b.classes: return cmp(a.classes, b.classes)
  cmp(a.types, b.types)

proc `<`*(a, b: Specificity): bool =
  cmp(a, b) < 0

proc selectorSpecificity*(sel: SelectorSet): Specificity =
  for s in sel.selectors:
    case s.kind
    of skId: inc result.ids
    of skClass: inc result.classes
    of skType: inc result.types
    of skUniversal: discard
    of skPseudo: inc result.classes
    for f in s.filters:
      case f.kind
      of skId: inc result.ids
      of skClass: inc result.classes
      of skType: inc result.types
      else: discard
    result.classes += s.pseudoClasses.len

# ----------------------------------------------------------------------------
# Pseudo-state pretty names
# ----------------------------------------------------------------------------

proc pseudoFromString*(s: string): (bool, PseudoState) =
  case s.toLowerAscii
  of "focus": (true, psFocus)
  of "hover": (true, psHover)
  of "disabled": (true, psDisabled)
  of "dark": (true, psDark)
  of "light": (true, psLight)
  else: (false, psFocus)

# ----------------------------------------------------------------------------
# Single-atom matching against a node
# ----------------------------------------------------------------------------

proc nodeClasses(node: TerminalNode): HashSet[string] =
  if node == nil: return
  if "class" in node.attributes:
    for c in node.attributes["class"].split({' ', '\t'}):
      if c.len > 0: result.incl(c)

proc nodeId(node: TerminalNode): string =
  if node == nil: return ""
  if "id" in node.attributes: node.attributes["id"]
  else: ""

proc matchAtom*(sel: Selector; ctx: NodeContext): bool =
  ## Match a single selector atom (type/id/class/universal) plus any
  ## attached pseudo-classes / compound filters against a single node +
  ## its pseudo-state set.
  if ctx.node == nil: return false
  let coreOk = case sel.kind
    of skUniversal: true
    of skType:
      # Case-insensitive tag-name match. The tag string is the
      # authoritative widget identity in IsoNim; we don't infer types
      # from `TerminalNodeKind` because the kind enum is intentionally
      # a small DOM-shape classifier, not a full widget taxonomy.
      sel.name.toLowerAscii == ctx.node.tag.toLowerAscii
    of skId: nodeId(ctx.node) == sel.name
    of skClass: sel.name in nodeClasses(ctx.node)
    of skPseudo:
      # Pseudo as a standalone atom: `:focus { ... }` selectors.
      let (found, ps) = pseudoFromString(sel.name)
      found and ps in ctx.pseudo
  if not coreOk: return false
  # Compound filters (e.g. `Button.primary` -> filter (skClass,"primary")).
  for f in sel.filters:
    case f.kind
    of skId:
      if nodeId(ctx.node) != f.name: return false
    of skClass:
      if f.name notin nodeClasses(ctx.node): return false
    of skType:
      let want = f.name.toLowerAscii
      let tag = ctx.node.tag.toLowerAscii
      if tag != want: return false
    else: discard
  for pc in sel.pseudoClasses:
    let (found, ps) = pseudoFromString(pc)
    if not found: return false
    if ps notin ctx.pseudo: return false
  return true

# ----------------------------------------------------------------------------
# Selector chain matching with descendant / child combinators
# ----------------------------------------------------------------------------

proc buildPath*(node: TerminalNode): seq[TerminalNode] =
  ## Root-to-node ancestor chain, inclusive. Used by the matcher.
  var cur = node
  while cur != nil:
    result.insert(cur, 0)
    cur = cur.parent

proc matchSelectorSet*(selSet: SelectorSet; ctx: NodeContext;
                       parentPseudo: TableRef[int, set[PseudoState]] = nil): bool =
  ## Match a SelectorSet (chain of atoms) against a node's ancestor
  ## chain. The last atom must match `ctx.node`. Earlier atoms must
  ## match an ancestor (descendant combinator) or the immediate parent
  ## (child combinator).
  ##
  ## `parentPseudo`: optional map from node-id to pseudo-state set, so
  ## `Screen:dark .panel` matches a `.panel` whose Screen ancestor has
  ## `:dark` set. If nil, only `ctx.node`'s pseudo-state is consulted
  ## for pseudo-classes on ancestor atoms (a small simplification —
  ## widget-tree pseudo-states usually live on container nodes).
  if selSet.selectors.len == 0: return false
  let path = buildPath(ctx.node)
  if path.len == 0: return false
  let lastIdx = selSet.selectors.len - 1
  # Last selector matches the leaf node.
  let lastAtom = selSet.selectors[lastIdx]
  if not matchAtom(lastAtom, ctx): return false
  if lastIdx == 0: return true
  # Walk the rest of the chain backwards. We try to find an ancestor
  # that matches; for child combinator only the immediate parent is
  # acceptable.
  var nodeIdx = path.len - 2  # start one above the leaf
  for selI in countdown(lastIdx - 1, 0):
    let atom = selSet.selectors[selI]
    let nextAtom = selSet.selectors[selI + 1]
    let mustBeImmediateParent = (nextAtom.combinator == ckChild)
    if nodeIdx < 0: return false
    if mustBeImmediateParent:
      let pseudoSet =
        if parentPseudo != nil and path[nodeIdx].id in parentPseudo:
          parentPseudo[path[nodeIdx].id]
        else: {}
      let parentCtx = NodeContext(node: path[nodeIdx], pseudo: pseudoSet)
      if not matchAtom(atom, parentCtx): return false
      dec nodeIdx
    else:
      var found = false
      while nodeIdx >= 0:
        let pseudoSet =
          if parentPseudo != nil and path[nodeIdx].id in parentPseudo:
            parentPseudo[path[nodeIdx].id]
          else: {}
        let ancCtx = NodeContext(node: path[nodeIdx], pseudo: pseudoSet)
        if matchAtom(atom, ancCtx):
          found = true
          dec nodeIdx
          break
        dec nodeIdx
      if not found: return false
  return true

proc anySelectorMatches*(rule: Rule; ctx: NodeContext;
                         parentPseudo: TableRef[int, set[PseudoState]] = nil):
                         (bool, Specificity) =
  ## Check if any of the rule's comma-separated selector groups match
  ## the given node. Returns `(matched, specificity)`. Specificity is
  ## the maximum among matching groups (CSS uses the first match's
  ## specificity, but max produces stable ordering).
  var bestSpec = Specificity()
  for selSet in rule.selectorSets:
    if matchSelectorSet(selSet, ctx, parentPseudo):
      let s = selectorSpecificity(selSet)
      if not (s < bestSpec):
        bestSpec = s
      result = (true, bestSpec)
  if not result[0]:
    return (false, Specificity())
