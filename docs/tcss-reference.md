# TCSS Reference

The TCSS engine (M5) is a Textual-compatible CSS dialect tailored for
terminal cell grids. It tokenizes Textual's stylesheets, parses them
into a typed rule tree, matches against the renderer's element tree,
and cascades the results into a per-node `ComputedStyle` cache.

The implementation lives at `src/isonim_tui/css/`. The full surface is
re-exported as `cssEngine` from the top-level `isonim_tui` module.

## Selectors

TCSS supports the same selector grammar as Textual. The following are
all matched by the parser and exercised by
`tests/test_css_match_specificity_corpus.nim` against a captured corpus
from the upstream Textual stylesheets:

- **Type selectors**: `Button`, `Static`, `Container`, …
  (matched against the renderer's `tagName`).
- **Class selectors**: `.primary`, `.disabled`.
- **Id selectors**: `#submit`.
- **Pseudo states**: `:focus`, `:hover`, `:disabled`, `:focus-within`,
  `:dark`, `:light`. The `:focus` repaint contract is gated by
  `tests/test_css_pseudo_state_focus_repaints.nim`.
- **Descendant combinator**: `Container Button`.
- **Child combinator**: `Container > Button`.
- **Compound selectors**: `Button.primary:focus`.

The match function returns a `(matched, specificity)` tuple. Specificity
is the standard CSS triple `(idCount, classCount, typeCount)`.

## Cascade

Every node receives a `ComputedStyle` value built by
`tests/test_css_cascade_full_chain.nim`'s pipeline:

1. Collect every rule whose selector matches the node, sorted by
   specificity then declaration order.
2. Walk in ascending order so later declarations win.
3. Apply inheritance for inheritable properties (`color`, `text-style`).
4. Resolve theme tokens (M6 — `$primary`, `$success`, etc.) against the
   active `Theme`.
5. Cache the result keyed by `(node.id, theme.id, focusedId, hoverId)`.

The cache invalidation rules are codified in
`tests/test_css_styles_cache_invalidation.nim`: structural mutations
(append/remove/setAttribute), focus changes, hover changes, and theme
swaps each evict matching entries.

## What actually reaches a cell

TCSS recognises the full Textual property grammar at the parser level,
and the cascade computes a correct `Styles` value for every property in
the table below. Reaching a *cell* is a separate question, and the
answer differs by property.

`src/isonim_tui/style_engine.nim` is the only path from cascade output
to paint. It lowers the following into the `node.styles` table the
compositor reads:

| Property | Notes |
| --- | --- |
| `color` | Foreground colour. Inherited by the compositor's tree walk. Resolves theme tokens. |
| `background` | Cell-background colour. Lowered to `background-color`. |
| `text-style` | Lowered for `bold`, `dim`, `italic`, `underline`, `reverse`. `strike`, `blink` and `overline` cascade correctly but have no cell representation yet. |
| `layer` | Numeric layer for the compositor's layered composite. |

The remaining properties below parse and cascade, but **nothing routes
their computed values into layout** — the layout modules take their
inputs from widget arguments, not from a `Stylesheet`:

| Property | Status |
| --- | --- |
| `width`, `height` | Parsed + cascaded. Not read by `layout/`. |
| `padding`, `margin` | Parsed + cascaded. Not read by `layout/`. |
| `border` | Parsed + cascaded. Widgets take a `BorderStyle` argument instead. |
| `align` | Parsed + cascaded. Not read by `layout/`. |
| `display`, `visibility` | Parsed + cascaded. Not read by the compositor's visibility check. |
| `dock` | Parsed + cascaded. `layout/dock.nim` is driven directly, not from CSS. |

Wiring those into layout is the natural follow-on to the style engine
and is not done. Until then, treat the second table as "the grammar is
there" rather than "the property works".

Other Textual properties parse cleanly but are intentionally ignored —
see the corpus tests for the full list of accepted-but-not-applied
keywords.

## Tailwind compatibility shim

`tests/test_css_tailwind_compat.nim` exercises a subset of Tailwind
utility names (`p-1`, `mx-auto`, `text-red-500`) and translates them
into TCSS declarations. This is opt-in via the parser's `tailwindMode`
flag; default usage parses canonical TCSS only.

## Error recovery

The parser implements a tolerant recovery strategy
(`tests/test_css_error_recovery.nim`). Unknown properties, malformed
values, and unterminated strings emit a diagnostic without aborting the
parse. Production stylesheets render uncertain rules into a recovery
list that callers can surface in their dev console.

## Theme tokens

Tokens (`$primary`, `$accent`, `$success`, `$warning`, `$error`, …)
resolve through the active `Theme`. The default themes
`textual-dark` and `textual-light` ship with the M6 `theme` module.
See `theming.md` for the full token list and how to register a custom
theme.
