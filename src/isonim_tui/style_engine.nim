## isonim_tui/style_engine.nim — the missing link between the M5/M6
## TCSS cascade and the M8 compositor.
##
## Before this module the cascade was a closed system: `css/*` and
## `theme/cascade.nim` could compute a fully-resolved `Styles` value for
## any node, but nothing ever called them from a painting path. The
## compositor reads `node.styles` — the flat `Table[string, string]` of
## *inline* styles that `TerminalRenderer.setStyle` writes — and
## `compositor.nim`'s own comment said the cascade "hands the compositor
## a materialised inline value in those styles anyway". Nothing
## performed that materialisation.
##
## This module performs it.
##
## Design
## ------
## The cascade output is *lowered into* `node.styles` before each paint
## rather than the compositor being taught to consume typed `Styles`
## objects. That direction was chosen deliberately:
##
##   * `node.styles` is the contract every widget and the IsoNim DSL
##     already writes through (`r.setStyle(node, "color", "red")`). One
##     sink for painted style keeps widgets, the DSL, and the cascade
##     interchangeable instead of forking the pipeline in two.
##   * Teaching the compositor to consume `Styles` would drag selector
##     matching, ancestor context, pseudo-state and the active theme
##     into the paint loop — the cascade would have to run per strip,
##     per frame, inside the code whose whole job is to be cheap.
##   * The compositor's strip cache keys on the hash of the cells a node
##     produces. Because lowered styles change those cells, cache
##     invalidation on a restyle is automatic; no new plumbing.
##
## Precedence
## ----------
## Inline styles win over cascaded ones, matching CSS (`style="…"` beats
## an author rule). The engine therefore records which keys it wrote for
## each node and, on the next pass, clears *only those* before writing
## again. A key a widget set through `setStyle` is never clobbered.
##
## No-op without CSS
## -----------------
## When no stylesheet source has been registered the pass returns
## immediately without touching a single node. An app that never calls
## `addCss` paints exactly the bytes it painted before this module
## existed.

import std/[strutils, tables]

import ./renderer
import ./css/properties
import ./css/styles as cssStyles
import ./css/match
import ./css/stylesheet
import ./theme/cascade as themeCascade
import ./theme/theme as themeMod

export themeCascade.ThemeContext, themeCascade.ThemeRegistry,
       themeCascade.newThemeContext, themeCascade.newThemeRegistry,
       themeCascade.registerTheme, themeCascade.activeTheme,
       themeCascade.subscribe, themeCascade.themeNames
export stylesheet.Stylesheet, stylesheet.StylesheetSource,
       stylesheet.newStylesheet, stylesheet.bumpRevision
export themeMod.Theme

type
  StyleEngine* = ref object
    ## Owns the app stylesheet, the theme registry, and the bookkeeping
    ## needed to re-materialise cascade output into `node.styles`
    ## without destroying inline styles.
    ##
    ## `ref object` for the same reason the compositor is: it is
    ## mutable scaffolding owned by the harness, not a value flowing
    ## through a public API. Everything it computes (`Styles`,
    ## `ThemeContext`, `PseudoState` sets) stays value-typed.
    sheet*: Stylesheet
    themes*: ThemeRegistry
    applied: Table[int, seq[string]]  ## nodeId -> keys this engine wrote

proc newStyleEngine*(): StyleEngine =
  StyleEngine(sheet: newStylesheet(),
              themes: newThemeRegistry(),
              applied: initTable[int, seq[string]]())

proc hasStyles*(eng: StyleEngine): bool {.inline.} =
  ## True when at least one stylesheet source has been registered. When
  ## false, `materialize` is a guaranteed no-op.
  eng != nil and eng.sheet != nil and eng.sheet.entries.len > 0

proc addCss*(eng: StyleEngine; css: string;
             source: StylesheetSource = ssUser;
             sourceName: string = "app.tcss") =
  ## Register a TCSS source with the engine's stylesheet. Bumps the
  ## sheet revision (see `Stylesheet.addCss`).
  eng.sheet.addCss(source, sourceName, css)

# ---------------------------------------------------------------------------
# Lowering: typed cascade output -> the string keys the compositor reads
# ---------------------------------------------------------------------------
#
# `compositor.parseColorOrDefault` understands `#RRGGBB`, `default`,
# `transparent`, and the sixteen ANSI palette names from `text/ansi`.
# Everything below lowers into exactly that vocabulary.

proc hexPair(v: uint8): string {.inline.} =
  const digits = "0123456789abcdef"
  result = newStringOfCap(2)
  result.add digits[int(v shr 4)]
  result.add digits[int(v and 0x0Fu8)]

proc toStyleString(c: CssColor): (bool, string) =
  ## Lower a `CssColor` to the string form the compositor parses.
  ## Returns `(false, "")` for values that carry no paintable colour
  ## (`currentcolor`, and any `$var` the theme failed to resolve) so the
  ## caller can leave the key unset rather than write a bogus value.
  case c.kind
  of cckRgb:
    (true, "#" & hexPair(c.r) & hexPair(c.g) & hexPair(c.b))
  of cckNamed:
    let (found, r, g, b) = lookupNamed(c.name)
    if found: (true, "#" & hexPair(r) & hexPair(g) & hexPair(b))
    else: (true, c.name)
  of cckAnsi:
    let lower = c.name.toLowerAscii
    (true, if lower.startsWith("ansi_"): lower[5 .. ^1] else: lower)
  of cckTransparent:
    (true, "transparent")
  of cckCurrent, cckVarRef:
    (false, "")

proc lower(s: cssStyles.Styles; dest: var seq[(string, string)]) =
  ## Project the subset of the computed style that the compositor can
  ## actually paint into `(key, value)` pairs.
  ##
  ## Only fields whose `*Set` flag is true are emitted: an unset field
  ## must not mask an inherited value, and must not make an app that
  ## registered no matching rule differ from one that registered no CSS
  ## at all.
  if s.colorSet:
    let (ok, v) = toStyleString(s.color)
    if ok: dest.add ("color", v)
  if s.backgroundSet:
    let (ok, v) = toStyleString(s.background)
    if ok: dest.add ("background-color", v)
  if s.textStyleSet:
    # The compositor's attribute vocabulary is bold / dim / italic /
    # underline / reverse. `strike`, `blink` and `overline` parse and
    # cascade correctly but have no cell representation yet, so they are
    # deliberately not lowered.
    if tsBold in s.textStyle:      dest.add ("bold", "true")
    if tsDim in s.textStyle:       dest.add ("dim", "true")
    if tsItalic in s.textStyle:    dest.add ("italic", "true")
    if tsUnderline in s.textStyle: dest.add ("underline", "true")
    if tsReverse in s.textStyle:   dest.add ("reverse", "true")
  if s.layerSet and s.layer.len > 0:
    dest.add ("layer", s.layer)

# ---------------------------------------------------------------------------
# Pseudo-state derivation
# ---------------------------------------------------------------------------

proc pseudoFor(node: TerminalNode; focusedId, hoveredId: int;
               isDark: bool): set[PseudoState] =
  ## Derive a node's pseudo-state set from live harness state. `:dark` /
  ## `:light` come from the active theme's polarity, `:disabled` from
  ## the attribute every interactive widget already sets, and
  ## `:focus` / `:hover` from the harness's focused / hovered ids.
  if node == nil: return
  if focusedId != 0 and node.id == focusedId: result.incl psFocus
  if hoveredId != 0 and node.id == hoveredId: result.incl psHover
  if node.attributes.getOrDefault("disabled", "").len > 0:
    result.incl psDisabled
  if isDark: result.incl psDark
  else: result.incl psLight

proc collectPseudo(node: TerminalNode; focusedId, hoveredId: int;
                   isDark: bool;
                   acc: TableRef[int, set[PseudoState]]) =
  if node == nil: return
  acc[node.id] = pseudoFor(node, focusedId, hoveredId, isDark)
  for ch in node.children:
    collectPseudo(ch, focusedId, hoveredId, isDark, acc)

# ---------------------------------------------------------------------------
# The materialisation pass
# ---------------------------------------------------------------------------

proc applyTo(eng: StyleEngine; node: TerminalNode;
             themeCtx: ThemeContext;
             allPseudo: TableRef[int, set[PseudoState]]) =
  if node == nil: return

  # 1. Retract what this engine wrote last pass. Keys written by
  #    `setStyle` were never recorded here, so they survive untouched.
  if node.id in eng.applied:
    for k in eng.applied[node.id]:
      node.styles.del(k)
    eng.applied.del(node.id)

  # 2. Cascade.
  let nodeCtx = NodeContext(node: node,
                            pseudo: allPseudo.getOrDefault(node.id))
  let computed = computeStylesThemed(eng.sheet, nodeCtx, themeCtx,
                                     allPseudo)

  # 3. Lower and write, yielding to any inline style already present.
  var lowered: seq[(string, string)]
  lower(computed, lowered)
  var written: seq[string]
  for (k, v) in lowered:
    if k in node.styles: continue   # inline wins
    node.styles[k] = v
    written.add k
  if written.len > 0:
    eng.applied[node.id] = written

  for ch in node.children:
    eng.applyTo(ch, themeCtx, allPseudo)

proc materialize*(eng: StyleEngine; root: TerminalNode;
                  focusedId: int = 0; hoveredId: int = 0) =
  ## Run the cascade over the whole tree and lower the result into each
  ## node's inline style table, so the next `Compositor.paint` reads
  ## computed styles. Called by `TerminalTestHarness.flush` immediately
  ## before painting.
  ##
  ## No stylesheet registered ⇒ no work and no mutation, so the painted
  ## bytes are bit-identical to the pre-cascade pipeline.
  if root == nil: return
  if not eng.hasStyles():
    return
  let theme = eng.themes.activeTheme()
  let themeCtx = newThemeContext(theme)
  let allPseudo = newTable[int, set[PseudoState]]()
  collectPseudo(root, focusedId, hoveredId, theme.dark, allPseudo)
  eng.applyTo(root, themeCtx, allPseudo)

proc setTheme*(eng: StyleEngine; name: string): bool =
  ## Switch the active theme and invalidate the cascade. The next
  ## `materialize` pass recomputes every node against the new theme's
  ## variable map; the caller is responsible for the repaint (the
  ## harness's `setTheme` does both).
  eng.themes.setTheme(name, eng.sheet)

proc setTheme*(eng: StyleEngine; t: themeMod.Theme): bool =
  ## Register `t` if it is new, then activate it by name.
  eng.themes.registerTheme(t)
  eng.themes.setTheme(t.name, eng.sheet)
