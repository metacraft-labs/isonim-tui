## isonim_tui/css/stylesheet.nim
##
## A `Stylesheet` is a collection of CSS sources (default user agent
## styles, user app stylesheet, inline `style="..."` declarations) and
## the rules they produce. The cascade walks every rule, finds the
## ones matching a node, sorts by (important, specificity, source-order)
## and stamps the typed values onto a fresh `Styles` object.
##
## Mirrors a much-reduced version of Textual's `Stylesheet` from
## `css/stylesheet.py`.

import std/[algorithm, tables]
import ../renderer
import ./parse
import ./match
import ./styles

type
  StylesheetSource* = enum
    ssDefault    ## the framework's built-in defaults
    ssUser       ## app-level stylesheet
    ssInline     ## `style="..."` attribute on a single node
    ssTailwind   ## expanded by the Tailwind compile-time DSL

  StylesheetSourceEntry* = object
    source*: StylesheetSource
    name*: string         ## debug label
    rules*: seq[Rule]
    appliesToNodeId*: int ## for inline: 0 means "applies to all" (unused)

  Stylesheet* = ref object
    entries*: seq[StylesheetSourceEntry]
    revision*: int  ## bumped on every mutation; used to invalidate
                    ## the per-widget `StylesCache`.

proc newStylesheet*(): Stylesheet =
  Stylesheet(entries: @[], revision: 0)

proc bumpRevision*(s: Stylesheet) {.inline.} =
  inc s.revision

proc addCss*(s: Stylesheet; source: StylesheetSource; sourceName: string;
             css: string) =
  ## Parse a CSS string and add its rules to the stylesheet under
  ## the given source. Errors are accumulated on the parse result and
  ## the stylesheet skips bad rules; downstream rules still apply.
  let parsed = parseCss(css, sourceName)
  s.entries.add(StylesheetSourceEntry(
    source: source,
    name: sourceName,
    rules: parsed.rules))
  bumpRevision(s)

proc addInlineDeclarations*(s: Stylesheet; nodeId: int;
                            decls: seq[Declaration]) =
  ## Add an inline declaration block targeting a specific node id. The
  ## declarations always match (no selector); specificity is
  ## conventionally the highest tier (mirrors browsers' inline-styles
  ## behaviour).
  var rule = Rule(declarations: decls,
                  sourceName: "inline:" & $nodeId,
                  sourceOrder: 1_000_000 + nodeId)
  s.entries.add(StylesheetSourceEntry(
    source: ssInline, name: "inline:" & $nodeId,
    rules: @[rule], appliesToNodeId: nodeId))
  bumpRevision(s)

proc clearInline*(s: Stylesheet; nodeId: int) =
  ## Remove inline declarations associated with a specific node id.
  var kept: seq[StylesheetSourceEntry]
  for e in s.entries:
    if e.source == ssInline and e.appliesToNodeId == nodeId:
      continue
    kept.add(e)
  s.entries = kept
  bumpRevision(s)

# ----------------------------------------------------------------------------
# Cascade
# ----------------------------------------------------------------------------

type
  CascadeMatch* = object
    rule*: Rule
    spec*: Specificity
    important*: bool  ## any declaration in the rule is `!important`
    sourceTier*: int  ## 0 default, 1 user, 2 inline (highest)

proc tierOf(s: StylesheetSource): int =
  case s
  of ssDefault: 0
  of ssTailwind: 1
  of ssUser: 2
  of ssInline: 3

proc collectMatches*(s: Stylesheet; ctx: NodeContext;
                     parentPseudo: TableRef[int, set[PseudoState]] = nil):
                     seq[CascadeMatch] =
  for entry in s.entries:
    let tier = tierOf(entry.source)
    if entry.source == ssInline:
      # Inline rules apply only to their target node id.
      if entry.appliesToNodeId == 0 or ctx.node == nil or
         entry.appliesToNodeId != ctx.node.id:
        continue
      for rule in entry.rules:
        var imp = false
        for d in rule.declarations:
          if d.important: imp = true; break
        result.add(CascadeMatch(
          rule: rule,
          spec: Specificity(ids: 1_000, classes: 0, types: 0),  # inline > #id
          important: imp,
          sourceTier: tier))
    else:
      for rule in entry.rules:
        let (matched, spec) = anySelectorMatches(rule, ctx, parentPseudo)
        if matched:
          var imp = false
          for d in rule.declarations:
            if d.important: imp = true; break
          result.add(CascadeMatch(
            rule: rule, spec: spec, important: imp, sourceTier: tier))

proc cmpCascade(a, b: CascadeMatch): int =
  ## Sort ascending: lower priority first. The cascade applies
  ## declarations in order, so later applications overwrite earlier
  ## ones. Order: !important first (by specificity asc → important
  ## with high spec wins), then source tier, then specificity, then
  ## insertion order.
  if a.important != b.important:
    return cmp(if a.important: 1 else: 0, if b.important: 1 else: 0)
  if a.sourceTier != b.sourceTier:
    return cmp(a.sourceTier, b.sourceTier)
  let specCmp = cmp(a.spec, b.spec)
  if specCmp != 0: return specCmp
  cmp(a.rule.sourceOrder, b.rule.sourceOrder)

proc applyCascade*(matches: seq[CascadeMatch]; dest: var Styles) =
  var sorted = matches
  sorted.sort(cmpCascade)
  for m in sorted:
    for d in m.rule.declarations:
      dest.applyValue(d.propertyKind, d.value)

proc computeStyles*(s: Stylesheet; ctx: NodeContext;
                    parentPseudo: TableRef[int, set[PseudoState]] = nil): Styles =
  ## End-to-end cascade for a node: collect matches, sort, apply.
  result = defaultStyles()
  let matches = collectMatches(s, ctx, parentPseudo)
  applyCascade(matches, result)
