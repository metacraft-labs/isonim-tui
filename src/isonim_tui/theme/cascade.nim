## isonim_tui/theme/cascade.nim
##
## Theme-aware extension of the M5 cascade.
##
## The base cascade in `css/stylesheet.nim` is theme-agnostic: it walks
## rules, computes specificity, and applies typed declarations. This
## module adds two extras:
##
##   1. *@dark / @light gating.* Rules tagged with `arDark` / `arLight`
##      only apply when the active theme's `dark` flag matches.
##   2. *$variable resolution.* `cckVarRef` colours (`$primary`, etc.)
##      are materialized into RGB via the active theme's generated
##      colour map.
##
## These features are exposed through `computeStylesThemed` — a thin
## wrapper around `computeStyles` that filters and rewrites the
## `Stylesheet`'s rules through a `ThemeContext` before delegating to
## the base cascade.

import std/[algorithm, tables]
import ../css/parse
import ../css/properties
import ../css/styles
import ../css/match
import ../css/stylesheet
import ./color as themeColor
import ./theme as themeMod

type
  ThemeContext* = object
    ## Snapshot of the active theme used during a single cascade pass.
    ## Built once per render frame; mutating fields require bumping the
    ## stylesheet revision so the per-widget cache is invalidated.
    theme*: themeMod.Theme
    isDark*: bool
    variables*: Table[string, string]   ## flat name -> CSS-string map
    variablesParsed*: Table[string, themeColor.Color]

proc newThemeContext*(t: themeMod.Theme): ThemeContext =
  result.theme = t
  result.isDark = t.dark
  result.variables = t.generate()
  for k, v in result.variables:
    let (ok, c) = themeColor.tryParseColor(v)
    if ok:
      result.variablesParsed[k] = c

proc gateRule(rule: Rule; ctx: ThemeContext): bool =
  ## True if the rule applies under this theme polarity. `arNone` /
  ## `arMedia` always pass through (we don't gate on @media yet — M11).
  case rule.atRule
  of arNone, arMedia: true
  of arDark: ctx.isDark
  of arLight: not ctx.isDark

proc resolveVarRef(name: string; ctx: ThemeContext): (bool, themeColor.Color) =
  if name in ctx.variablesParsed:
    return (true, ctx.variablesParsed[name])
  (false, themeColor.transparent())

proc rewriteValue(value: PropertyValue; ctx: ThemeContext): PropertyValue =
  ## Materialize `cckVarRef` colours via the theme's variable map.
  ## Other property values pass through unchanged.
  if value.kind == vkColor and value.colorVal.kind == cckVarRef:
    let (found, col) = resolveVarRef(value.colorVal.name, ctx)
    if found:
      return colorValue(rgbCss(col.r, col.g, col.b,
                               (col.a * 255.0).int.uint8))
    return value
  if value.kind == vkColor and value.colorVal.kind == cckNamed:
    # Allow named-fallback through the theme: `$accent` styled as a
    # bare name can come through as `cckNamed`. If the name resolves
    # via the theme (e.g. `accent-darken-1`), use that.
    let nm = value.colorVal.name
    if nm in ctx.variablesParsed:
      let col = ctx.variablesParsed[nm]
      return colorValue(rgbCss(col.r, col.g, col.b,
                               (col.a * 255.0).int.uint8))
  value

proc rewriteDeclaration(d: Declaration; ctx: ThemeContext): Declaration =
  result = d
  result.value = rewriteValue(d.value, ctx)

proc rewriteRule(rule: Rule; ctx: ThemeContext): Rule =
  result = rule
  result.declarations = @[]
  for d in rule.declarations:
    result.declarations.add(rewriteDeclaration(d, ctx))

proc computeStylesThemed*(s: Stylesheet; nodeCtx: NodeContext;
                          themeCtx: ThemeContext;
                          parentPseudo: TableRef[int,
                              set[PseudoState]] = nil): Styles =
  ## Theme-aware cascade. Filters rules by `@dark` / `@light` polarity,
  ## resolves `$variable` colours, then applies the cascade.
  result = defaultStyles()
  var matches = collectMatches(s, nodeCtx, parentPseudo)
  # Filter out rules whose @dark/@light doesn't match.
  var kept: seq[CascadeMatch] = @[]
  for m in matches:
    if gateRule(m.rule, themeCtx):
      var rewritten = m
      rewritten.rule = rewriteRule(m.rule, themeCtx)
      kept.add(rewritten)
  applyCascade(kept, result)

# ---------------------------------------------------------------------------
# Application-level state: active theme + change notification
# ---------------------------------------------------------------------------

type
  ThemeRegistry* = ref object
    ## Tracks the registered themes and the currently active one. Held
    ## by `App` (M11+); for M6 it's a standalone object the renderer
    ## owns. `setTheme` bumps the stylesheet revision to invalidate
    ## the per-widget styles cache, which causes a fresh cascade and a
    ## repaint of every cell whose computed style changed.
    themes*: Table[string, themeMod.Theme]
    activeName*: string
    onChange*: seq[proc(t: themeMod.Theme) {.closure.}]

proc newThemeRegistry*(): ThemeRegistry =
  result = ThemeRegistry(themes: themeMod.builtinThemes(),
                         activeName: "textual-dark",
                         onChange: @[])

proc registerTheme*(reg: ThemeRegistry; t: themeMod.Theme) =
  reg.themes[t.name] = t

proc activeTheme*(reg: ThemeRegistry): themeMod.Theme =
  reg.themes[reg.activeName]

proc setTheme*(reg: ThemeRegistry; name: string;
               sheet: Stylesheet = nil): bool =
  ## Switch the active theme. Returns false if the name isn't
  ## registered. When `sheet` is supplied, bumps its revision so the
  ## styles cache invalidates and the next cascade pass produces fresh
  ## values.
  if name notin reg.themes: return false
  if reg.activeName == name: return true
  reg.activeName = name
  if sheet != nil:
    bumpRevision(sheet)
  let active = reg.activeTheme()
  for cb in reg.onChange:
    cb(active)
  true

proc subscribe*(reg: ThemeRegistry;
                cb: proc(t: themeMod.Theme) {.closure.}) =
  reg.onChange.add(cb)

proc themeNames*(reg: ThemeRegistry): seq[string] =
  for k in reg.themes.keys: result.add(k)
  result.sort()
