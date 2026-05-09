# Widget Gallery

The M11–M21 widget set ports Textual's full Tier-1 / Tier-2 / Tier-3
catalogue. Every widget builds against the production
`TerminalRenderer`, so the same code drives the M9 `PosixDriver`, the
M10 `WindowsDriver`, the M2 `HeadlessDriver`, and the M26 `WebDriver`.

Each entry below shows the constructor signature plus a minimal usage
snippet. Mount the returned widget into the tree with
`r.appendChild(parent, widget.node)`.

## Tier-1a — Foundational primitives (M11)

### Static

A pre-formatted block of text. Optional border, optional vertical
scroll. Used as the building block for higher-level widgets.

```nim
let s = newStatic(r, "Hello\nfrom isonim-tui",
                  width = 30, height = 5,
                  border = bsRound, scrollable = true)
r.appendChild(root, s.node)
```

### Label

A single-statement Rich-Text label. Wraps to the configured `width`
when non-zero.

```nim
let lbl = newLabel(r, "[bold]hello[/bold]", width = 20)
```

### Container

Layout block with optional border and keyboard scrolling. Use it as the
parent for a vertical stack of children.

```nim
let c = newContainer(r, width = 40, height = 10,
                     border = bsSolid, scrollable = true)
r.appendChild(root, c.node)
c.append(child1.node)
c.append(child2.node)
```

### Placeholder

A debug-only widget that renders a labelled solid block. Handy when
roughing out a layout.

### Rule

A horizontal or vertical separator glyph. `RuleOrientation.roHorizontal`
draws `─`-style glyphs across the width; `roVertical` draws a column.

## Tier-1b — Interactive widgets (M12)

### Button

Click-to-activate widget with five variants (`bvDefault`, `bvPrimary`,
`bvSuccess`, `bvWarning`, `bvError`). Activates on Enter, Space, or
mouse click.

```nim
let b = newButton(r, "Save", variant = bvPrimary,
                  onClick = proc() = vm.save())
```

### Switch

Two-state on/off toggle. Drives via Space or mouse click. Reports state
changes through `onChange`.

### Checkbox

Stateful checkbox. Same activation contract as `Switch`; renders with
the platform glyph set.

### RadioButton / RadioSet

Mutually exclusive selection group. The `RadioSet` owns several
`RadioButton` children and maintains the single-selection invariant.

## Tier-1c — Input (M13)

### Input

Single-line text editing with grapheme-aware cursor, password masking,
suggestions, validators, and `onChange` / `onSubmit` callbacks.

```nim
let inp = newInput(r, placeholder = "Search…",
                   width = 30, border = bsRound,
                   onChange = proc(s: string) = vm.setQuery(s))
```

## Tier-2 — Composite widgets (M14)

### Tabs / TabbedContent / ContentSwitcher

`Tabs` renders a tab bar; `ContentSwitcher` shows one of N children;
`TabbedContent` glues the two together for a Textual-equivalent tab
view.

### ListView

Vertical scrollable list. Keyboard navigation (`up` / `down` / `home` /
`end` / `pageup` / `pagedown`).

```nim
let lv = newListView(r,
  items = @[ListItem(id: "1", label: "First"),
            ListItem(id: "2", label: "Second")],
  width = 30, viewportHeight = 8, border = bsRound)
```

### OptionList

Like `ListView` but with a richer rendering hook (per-item Rich Text)
and explicit highlighted/selected state.

### Select

Dropdown that combines a button-like header with an `OptionList`
overlay.

### Collapsible

Accordion-style expandable section. Animated expand/collapse via the
M7 animator.

### Modal

Overlay container. Holds focus, drives a backdrop, and animates in.

### Toast

Auto-dismissing notification. Renders at a configured corner and fades
out via the animator.

### LoadingIndicator

Spinner widget. Cycles through a glyph set on the animator's frame
clock.

### Image

Embeds an image via Kitty graphics, iTerm2 inline images, or a Sixel
fallback. Falls back to a Unicode quadrant block grid when the
terminal speaks none of those.

## Tier-3a — DataTable (M17)

### DataTable

Virtualised rows + columns with header pinning, sortable columns, and
keyboard cell selection. Handles 1000s of rows by only rendering the
visible viewport.

```nim
let dt = newDataTable(r,
  columns = @[ColumnDef(key: "id", label: "ID", width: 4),
              ColumnDef(key: "name", label: "Name", width: 20)],
  rows = @[RowData(cells: @["1", "alpha"]),
           RowData(cells: @["2", "beta"])],
  viewportHeight = 10, border = bsSolid)
```

## Tier-3b — Trees (M18)

### Tree

Generic expandable/collapsible tree. Lazy children loader.

### DirectoryTree

Tree specialised for filesystem paths. Lists children via `os.walkDir`
on expansion.

```nim
let t = newDirectoryTree(r, path = "/home/me/project",
                         width = 40, viewportHeight = 12,
                         border = bsRound)
```

## Tier-3c — TextArea (M19)

### TextArea

Multi-line code editor. Soft-wrap, undo/redo (depth configurable), tab
size, optional read-only mode, optional language hint
(`"python"` / `"nim"` enable a stub keyword highlighter; tree-sitter
integration deferred).

```nim
let ta = newTextArea(r, text = "fn main()\n  echo 1",
                     width = 60, viewportHeight = 20,
                     language = "nim")
```

## Tier-3d — Markdown (M20)

### Markdown / MarkdownViewer

Renders CommonMark with the M11/M5 widget pipeline. Headings, lists,
code blocks, block quotes, tables, links — all styled through the TCSS
cascade.

```nim
let md = newMarkdown(r, source = readFile("README.md"),
                     width = 80, border = bsRound)
```

## Tier-3e — Output / chrome (M21)

### RichLog

Append-only log with optional auto-follow, configurable max-line ring
buffer, and optional soft wrap. Keyboard scrolling.

### Log

Plain-text variant of RichLog. Smaller code path; same auto-follow /
ring-buffer story.

### ProgressBar

Animated progress bar. The animator drives smooth fill animations.

### Sparkline

Compact data visualisation. Three summary modes: `sumMax`, `sumMean`,
`sumMin`.

```nim
let sp = newSparkline(r, data = @[1.0, 3.0, 2.0, 4.5, 7.0],
                      width = 40, height = 1, summary = sumMax)
```

### Header

App chrome that docks at the top. Title + subtitle + clock.

### Footer

Key-binding chrome that docks at the bottom. Compact / verbose mode.

### Welcome

The Textual welcome screen. Pure debugging convenience.

## Where to find more

Every widget has a real-stack snapshot test under `tests/`. Search for
`test_<widget>_*.nim` to see worked examples — every test mounts the
widget under `TerminalTestHarness`, drives a scenario through the
M2 pilot, and gates the output against a stored golden.
