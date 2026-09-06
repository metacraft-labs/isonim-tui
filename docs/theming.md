# Theming

The M6 theming module ships two reference themes (`textual-dark` and
`textual-light`), a token-driven `ColorSystem`, and a runtime theme
swap path. The implementation lives at `src/isonim_tui/theme.nim` and
related modules; it's re-exported by `isonim_tui` as `themeEngine`.

## ColorSystem

A `ColorSystem` is a structured palette that yields per-token colours
plus their derived shades (luminosity-spread tints and accents). The
system mirrors Textual's `ColorSystem` byte-for-byte — the
`tests/test_colorsystem_luminosity_spread.nim` and
`tests/test_textual_dark_byte_identical.nim` corpora gate compatibility.

Each token resolves to a foreground colour, a matching background, and
a configurable contrast ramp. Common tokens:

- `$primary`, `$primary-darken-1`, `$primary-lighten-2`, …
- `$accent`, `$accent-darken-1`, …
- `$success`, `$warning`, `$error`
- `$background`, `$surface`, `$panel`
- `$foreground`, `$foreground-muted`

## Theme

A `Theme` bundles a name, a `ColorSystem`, and the explicit overrides
the theme cares about (e.g. `textual-light` overrides the surface and
panel tokens). The two reference themes:

- `textual-dark` — default dark theme. Background: a deep blue-grey.
- `textual-light` — light theme. Background: a near-white surface.

## Runtime swap

`h.setTheme` switches the active theme and repaints: it drops the
compositor's strip cache, bumps the stylesheet revision so the cascade
recomputes, and flushes. Any node whose computed style resolves a `$`
token paints its new colour on the next frame.

`h.setTheme` takes either a registered theme's *name* or a `Theme`
value (which it registers first). It returns `false` — and repaints
nothing — when the name is not registered.

```nim
import isonim_tui

let h = newTerminalTestHarness(60, 20)
# ... mount ...
h.addCss("Button { color: $primary; }")

discard h.setTheme("textual-light")     # by registered name
discard h.setTheme(builtinTextualDark()) # or by value
```

`tests/test_css_cascade_reaches_compositor.nim` proves the swap reaches
painted cells: it mounts a harness, reads `h.cellAt`, and asserts the
`$primary` colour changes from `#0178D4` to `#004578` across the swap.
Pseudo states `:dark` and `:light` cooperate with the theme switch —
see `tests/test_at_dark_at_light_full_app.nim` for the cascade-level
gating and the `@dark` / `@light` case in the test above for the
painted-cell version.

## Custom themes

A `Theme` is a flat record of colour *strings* (Textual defines its
themes as literals, and this port keeps that interface so the values
stay byte-identical). Build one with the `theme` constructor and hand
it to `setTheme`, which registers it under its own name:

```nim
import isonim_tui

let myTheme = theme(
  name       = "midnight",
  primary    = "#12bfff",
  accent     = "#bd80ff",
  background = "#0c0e14",
  surface    = "#161922",
  foreground = "#f3f4ff",
  dark       = true)

let h = newTerminalTestHarness(80, 24)
discard h.setTheme(myTheme)
```

To register a theme without activating it, use the registry directly:

```nim
h.themeRegistry.registerTheme(myTheme)
echo h.themeRegistry.themeNames()
echo h.activeThemeName
```

## How a token reaches a cell

The cascade does not paint. `src/isonim_tui/style_engine.nim` runs it
over the mounted tree on every `flush()` and lowers the computed
`Styles` into the flat `node.styles` table that the compositor reads,
resolving `$token` references through the active theme on the way.
Widgets that set a style directly (`r.setStyle(node, "color", …)`) win
over cascaded values, matching CSS's inline-beats-author rule.

An app that never calls `addCss` never touches the cascade: the pass
returns immediately and paints exactly the bytes it would have painted
without a style engine at all.

## Token-aware widgets

Textual-style class chains (`.primary > Button`, `Button:focus`,
`Button:disabled`) work end-to-end because the parser, matcher, and
cascade each preserve the token reference until the style engine
materialises it at paint time.

The cross-platform compatibility test
`tests/test_isonim_theme_token_compat.nim` checks that the same token
names flow through to the IsoNim Cocoa / GPUI / web backends — so a
shared stylesheet can target multiple platforms without per-target
forks.
