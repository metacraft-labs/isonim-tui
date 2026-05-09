# Changelog

A milestone-by-milestone record of the 27-milestone IsoNim-TUI journey.
Entries are sourced from the actual commit history (`git log`); each
section expands the commit summary into 1–3 sentences of context.

## M27 — Production Release: Docs, Examples, Catalog (current)

The stamp-of-readiness milestone. Ships `docs/` covering every
subsystem, eight standalone demo apps under `examples/`, the
`FEATURE_PARITY.md` feature checklist, and this `CHANGELOG.md`. The
mandatory `test_demos_compile_and_run` mounts each example under
`TerminalTestHarness`, drives a recorded scenario, and gates against
a stored golden snapshot.

## M26 — WebDriver: Textual-compatible D/M/P packet driver

Adds `drivers/web_driver.nim`, a `Driver` implementation that emits
Textual's D/M/P packet stream over stdio. Pairs with the
`isonim-tui-serve` sibling repo, which provides a WebSocket bridge to
xterm.js so a TUI app can serve itself to a browser. Live-browser
Playwright e2e is explicitly deferred to a follow-up.

## M25 — Advanced introspection: Recording, Replay, Time-Travel, Layout debug

Adds the `Recording`/`Replayer` pipeline, byte-identical replay
(`test_record_replay_byte_identical`), an HTML timeline view
(`test_timeline_html_diffable`), and the layout assertions
`assertNoOverlap` / `assertSinglePassPaint`. Recording captures every
event + paint stamped against virtual time so a full session
round-trips through serialisation with no drift.

## M24 — Continuous Benchmarking: github-action-benchmark format + CI

Adds `benchmarks/` with one source per metric, `scripts/collect-bench-
mark-metrics.sh` to produce `bench-results/benchmark_results.json` in
the github-action-benchmark schema, and `scripts/render-bench-report.sh`
for the standalone HTML report. CI publishes the JSON so regressions
flag automatically against a moving baseline.

## M23 — Textual Compatibility Suite: initial 8 ports

Lands `examples/ports/` with eight Nim ports of Textual's own
`tests/snapshot_tests/snapshot_apps/` — `button_outline`,
`button_widths`, `placeholder_disabled`, `rules`, `sparkline`,
`progress_gradient`, `listview_index`, and `data_table_row_labels`.
The `test_textual_compat` suite mounts each port and gates against an
isonim-tui-recorded golden, with a tagged-failure registry left empty
so every port is expected to pass.

## M22 — Cross-Platform Task App: shared core across web and TUI

Demonstrates the IsoNim Layer-1/2/3/4 split end-to-end. The task app's
ViewModel (`examples/task_app/core/vm.nim`) is byte-identical between
the TUI target and the web target; the `tui/leaves.nim` and `web/`
modules pick the platform-specific widgets. Five canonical states ship
as snapshots in `test_task_app_tui_snapshot_five_states`.

## M21 — Tier-3e widgets: RichLog, Log, ProgressBar, Sparkline, Header, Footer, Welcome

Wraps up the widget catalogue with output / chrome widgets. RichLog
adds a configurable ring buffer + auto-follow; ProgressBar threads the
M7 animator for smooth fills; Sparkline ports Textual's three
summary-function variants. Header / Footer dock at top / bottom with
title + key-binding rows.

## M20 — Tier-3d: Markdown + MarkdownViewer

Adds `widgets/markdown.nim` — a CommonMark parser + renderer. Headings,
paragraphs, lists, code blocks, block quotes, links, and tables flow
through the M5 cascade so themes apply uniformly. The
`test_markdown_renders_textual_readme` test renders Textual's actual
README to ensure realistic content survives.

## M19 — Tier-3c: TextArea (multi-line code editor)

Multi-line editor with grapheme-aware cursor, soft wrap, configurable
tab size, undo/redo (depth configurable), read-only mode, and stub
syntax highlighting for Python and Nim keywords. Tree-sitter integration
was scoped out — the API surface is stable, ready for a later upgrade.

## M18 — Tier-3b: Tree + DirectoryTree

Adds the generic `Tree` widget with lazy children loading, plus a
specialised `DirectoryTree` that lists filesystem paths via
`os.walkDir`. `test_directory_tree_real_fs` exercises against a real
on-disk tree to cover lazy expansion semantics.

## M17 — Tier-3a: DataTable

Virtualised rows + columns. Sortable headers, selection, fixed
columns, and a viewport-aware paint path so 1000-row tables stay
cheap to scroll. The `test_datatable_virtualisation_perf` benchmark
gates the perf contract.

## M16 — Command Palette: fuzzy matching + Provider system

Adds `command/palette.nim` and `command/fuzzy.nim`. Commands aren't a
static list — apps register Provider objects that yield commands lazily
based on the active query. The fuzzy matcher implements Sublime-style
scoring (contiguous matches > word-boundary > gapped) gated by a
captured Textual corpus.

## M15 — Workers: background tasks

Per-harness worker manager + cooperative cancellation + a `{.work.}`
decorator macro. State machine
(`pending → running → completed | cancelled | failed`) is exhaustively
tested; cancellation flips a flag that workers check on each yield.
`test_workers_isolated_per_harness` proves no cross-talk between
parallel harnesses.

## M14 — Tier-2 widgets

Eleven widgets in one milestone: Tabs, TabbedContent, ContentSwitcher,
ListView, OptionList, Select, Collapsible, Modal, Toast, LoadingIndicator,
and Image. Modal lands the focus-trap contract; Toast wires into the M7
animator for fade-out; Image probes terminal capabilities for the right
protocol (Kitty / Unicode fallback shipped).

## M13 — Tier-1c: Input widget

Single-line text editing with grapheme-aware cursor, password masking,
suggestions, validators, and `onChange` / `onSubmit` callbacks. The
`test_input_typing_and_cursor` and `test_input_grapheme_cursor` corpora
cover the editing semantics.

## M12 — Focus manager + Tier-1b widgets

Adds `focus/manager.nim` (Tab / Shift-Tab navigation, focus traps,
programmatic focus mutation) plus the interactive widget tier: Button,
Switch, Checkbox, RadioButton, RadioSet. Activation contract (Enter /
Space / mouse click) is uniform across the tier.

## M11 — Tier-1a widgets: Static, Label, Container, Placeholder, Rule

Foundational primitives. Every higher-tier widget builds on these. The
`test_m11_widget_snapshot_coverage` corpus locks in the per-widget
appearance.

## M10 — WindowsDriver: ReadConsoleInputW, VT processing, parity with PosixDriver

Win32-native driver covering raw input via `ReadConsoleInputW`, console
VT mode, ctrl-c handler, and resize. `test_windows_driver_*` tests run
on Windows CI and assert byte-parity with the POSIX driver where the
APIs overlap.

## M9 — PosixDriver: termios, alt-screen, mouse, resize, signals

The production POSIX driver: termios raw mode, alt-screen entry/exit,
mouse SGR encoding, SIGWINCH self-pipe for resize, SIGTERM clean exit.
`test_posix_driver_real_pty` opens an actual pty for end-to-end I/O
testing.

## M8 — Compositor: strip cache, dirty regions, layered output, line diff

Single-pass paint pipeline. Strip cache keys identical lines; dirty
region tracking minimises ANSI emission; layered overlays support
modals / toasts. `test_compositor_idle_no_writes` proves zero bytes
leave the driver when nothing changed.

## M7 — Animation engine: Animator, 33 easings, blend protocol, animate() API

Frame-driven animator with byte-parity easing curves
(`test_easing_byte_parity`), gamma-correct colour blending, and a
clean `animate(...)` callsite that targets any property. The harness
runs against a virtual clock so animations advance deterministically
in tests.

## M6 — Theming: ColorSystem, textual-dark/light, luminosity blending

Token-driven theming. `ColorSystem` mirrors Textual's
luminosity-spread byte-for-byte; `textual-dark` and `textual-light`
ship as reference themes. Runtime swap (`test_runtime_theme_switch`)
invalidates the M5 cache.

## M5 — TCSS engine: tokenize, parse, match, cascade, properties, cache

Full Textual-compatible CSS dialect. Tokenizer + parser cover the
upstream stylesheet corpus
(`test_css_tokenize_real_textual_corpus`); selector matcher returns
specificity triples; cascade applies inheritance + theme tokens; the
result is cached keyed by `(node.id, theme.id, focusedId, hoverId)`.

## M4 — Input parser corpus + adapter wrapping nim-termctl's parser

Wraps `nim-termctl`'s byte-level parser into the
`TerminalEvent`-emitting input layer. Comprehensive corpus tests
(`test_input_simple_keys_corpus`, `test_input_mouse_sgr_corpus`,
`test_input_kitty_protocol`) cover the input grammar.

## M3 — Layout engine integration: cell-snapped Yoga, dock, arrange, reflow

Binds Yoga via FFI for flexbox layout. Cell-snapping rounds half-cell
positions (`test_layout_cell_snap_integer_real_yoga`); dock / arrange
implement Textual's dock layout for top/bottom/left/right pinning.
Reflow delta tracking minimises repaints on resize.

## M2 — TerminalTestHarness: HeadlessDriver, Pilot, Introspection, 6-format snapshots

The user-facing test API. Bundles renderer + headless driver +
compositor + virtual clock + node-id counter + event log + introspection
into one ref object. Six snapshot formats (plaintext / ansi / cellmap /
svg / annotated-svg / treedump) round out the diagnostic surface.

## M1 — Text width, grapheme clusters, Content/Rich Text, ANSI encoding

Wide-character + zwj-emoji-safe cell width measurement. Grapheme
cluster iteration; Content type for styled text spans; ANSI SGR
encoding (truecolor + minimal-transition).
`test_grapheme_width_emoji_zwj` covers the corner cases.

## M0 — Foundation

The starting surface: `Cell` / `Strip` / `ScreenBuffer` value types
with cached display width and content hash; production
`TerminalRenderer` satisfying the `RendererBackend` concept;
value-typed event system parity with `isonim/web/dom_api.nim`. Per-thread
node-id counter as `{.threadvar.}` so parallel harnesses don't alias.
