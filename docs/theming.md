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

`tests/test_runtime_theme_switch.nim` proves the swap repaints every
node whose computed style depends on a token. Pseudo states `:dark`
and `:light` cooperate with the theme switch — see
`tests/test_at_dark_at_light_full_app.nim` for an end-to-end harness
test driving both states off a single stylesheet.

```nim
import isonim_tui

let h = newTerminalTestHarness(60, 20)
# ... mount ...
h.setTheme(textualDarkTheme())   # explicit dark
h.setTheme(textualLightTheme())  # swap to light → cache invalidates
```

After a theme swap the M5 cascade cache evicts every entry whose
selector touched the swapped tokens, so the next paint reflects the
new colours without stale results.

## Custom themes

To register a custom theme, build a `ColorSystem` and wrap it in a
`Theme`:

```nim
import isonim_tui

let myColors = ColorSystem(
  primary: parseColor("#12bfff"),
  accent:  parseColor("#bd80ff"),
  background: parseColor("#0c0e14"),
  surface:    parseColor("#161922"),
  foreground: parseColor("#f3f4ff"))

let myTheme = Theme(name: "midnight", colorSystem: myColors)

let h = newTerminalTestHarness(80, 24)
h.setTheme(myTheme)
```

## Token-aware widgets

Every widget that renders text or borders consults the active theme
through the M5 cascade. Textual-style class chains
(`.primary > Button`, `Button:focus`) work end-to-end because the
parser, matcher, and cascade each preserve the token reference until
paint time.

The cross-platform compatibility test
`tests/test_isonim_theme_token_compat.nim` checks that the same token
names flow through to the IsoNim Cocoa / GPUI / web backends — so a
shared stylesheet can target multiple platforms without per-target
forks.
