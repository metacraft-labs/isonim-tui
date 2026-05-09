# Command Palette

The M16 command palette is a Textual-equivalent fuzzy command launcher.
Implementation lives at `src/isonim_tui/command/`, surfaced by the
top-level module as `fuzzyMod` and `paletteMod`.

## Provider system

Commands aren't a static list. Apps register **providers** — small
objects that yield commands lazily based on the current query. This is
how the upstream Textual palette mixes "open file", "switch theme",
and per-app commands without a global registry.

```nim
type Provider* = object
  name*: string
  search*: proc(query: string): seq[Command]

type Command* = object
  id*: string
  title*: string
  subtitle*: string
  run*: proc()
```

Each provider's `search(query)` runs synchronously on the palette's
worker tick. Producing commands lazily means a provider can defer
expensive computation (filesystem walks, RPC calls) until the user has
typed enough characters to be specific.

## Fuzzy matcher

The fuzzy matcher (`isonim_tui/command/fuzzy.nim`) implements a
Sublime-style score: contiguous matches score higher than gapped
matches; matches at word boundaries weight extra; case-insensitive by
default. The corpus in
`tests/test_fuzzy_matcher_corpus.nim` exercises the scoring surface
against captured Textual fixtures.

The matcher returns `(score, indices)` — `indices` is the set of
positions the matcher chose to highlight. The palette UI uses those
indices to bold-highlight matched characters.

## Open / search / run

`tests/test_palette_open_search_run.nim` shows the canonical flow:

```nim
let palette = newPalette()
palette.register newProvider(
  name = "themes",
  search = proc(q: string): seq[Command] =
    @[Command(id: "dark",  title: "Switch to dark theme",
              run: proc() = h.setTheme(textualDarkTheme())),
      Command(id: "light", title: "Switch to light theme",
              run: proc() = h.setTheme(textualLightTheme()))]
      .filter(proc(c: Command): bool = fuzzyMatch(q, c.title).matched))

palette.open()
palette.setQuery("dark")
let visible = palette.results
palette.run(visible[0].id)
```

The palette is a Modal under the hood, so it picks up focus trapping
and keyboard dismissal automatically.

## Default keybinding

By convention the palette opens on `ctrl+p`. Wire that into your app's
key handler — the palette doesn't install a global binding because
applications may want their own shortcut convention.
