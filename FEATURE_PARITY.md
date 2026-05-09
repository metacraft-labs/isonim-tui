# Feature Parity vs. Textual

This document maps each Textual subsystem to its IsoNim-TUI equivalent
and grades the parity. The grading scale:

- **full** — feature-complete byte-for-byte (or with documented
  trivial differences only).
- **mostly** — feature-complete with minor known gaps documented.
- **partial** — core happy path lands; advanced features deferred.
- **not-yet** — an explicit non-goal or planned for after M27.

| Textual Subsystem | IsoNim-TUI Equivalent | Parity Status | Notes |
| --- | --- | --- | --- |
| Reactive core (`reactive`, `Watch`) | `isonim/core/signals` (sibling repo, consumed via path import) | full | The reactive primitives live in `isonim/`, not in this repo. Same Signal/Effect/Memo surface. |
| App lifecycle (`App`, `mount`, `compose`, `on_*`) | `TerminalTestHarness.mount` + per-app composition root | mostly | The harness covers the test-time lifecycle; production apps wire the same `mount` into `PosixDriver` / `WindowsDriver`. The `compose` decorator pattern is replaced by an explicit Nim builder proc. |
| Driver layer (`PosixDriver`, `WindowsDriver`, `WebDriver`, `HeadlessDriver`) | `drivers/posix_driver.nim`, `drivers/windows_driver.nim`, `drivers/web_driver.nim`, `drivers/headless_driver.nim` | full | All four drivers implement the same `Driver` concept. Real-pty / Win32 console / WebSocket packet bridge / synchronous in-memory respectively. |
| Compositor | `compositor.nim` with strip cache, dirty regions, layered overlays | full | Single-pass paint, line diff, idle paths covered by `test_compositor_*` corpus. |
| TCSS engine (tokenize / parse / match / cascade) | `css/css.nim` | mostly | Selector grammar + cascade + cache + tailwind-compat shim. The 12 load-bearing properties are honoured at paint; other Textual properties parse cleanly but are intentionally ignored (catalogued in `docs/tcss-reference.md`). |
| ColorSystem | `theme/color_system` (in `theme.nim`) | full | Luminosity spread byte-identical with Textual; `test_colorsystem_luminosity_spread.nim`, `test_textual_dark_byte_identical.nim`. |
| Theming (`textual-dark`, `textual-light`, runtime swap) | `theme.nim` reference themes + `setTheme` | full | Cache invalidation on swap covered by `test_runtime_theme_switch.nim`. |
| Animator (33 easings, key cancellation, scalar + colour blend) | `animation/animator.nim`, `animation/easing.nim`, `animation/scalar.nim` | full | Byte-parity with Textual's `_easing.py` corpus (`test_easing_byte_parity.nim`). |
| Focus Manager (Tab navigation, focus traps) | `focus/manager.nim` | full | Tab order, traps, programmatic focus, blur/focus events (`test_focus_tab_order.nim`, `test_modal_focus_trap_real.nim`). |
| Tier-1 widgets (Static, Label, Container, Placeholder, Rule, Button, Switch, Checkbox, RadioButton, RadioSet, Input) | `widgets/static.nim`, `label.nim`, `container.nim`, `placeholder.nim`, `rule.nim`, `button.nim`, `switch.nim`, `checkbox.nim`, `radio_button.nim`, `radio_set.nim`, `input.nim` | full | Per-widget snapshot tests cover the activation/hover/focus contract. |
| Tier-2 widgets (Tabs, TabbedContent, ContentSwitcher, ListView, OptionList, Select, Collapsible, Modal, Toast, LoadingIndicator, Image) | `widgets/tabs.nim`, `tabbed_content.nim`, `content_switcher.nim`, `listview.nim`, `option_list.nim`, `select.nim`, `collapsible.nim`, `modal.nim`, `toast.nim`, `loading_indicator.nim`, `image.nim` | full | Modal focus-trap, animation frames, toast auto-dismiss, image protocol fallback all covered. |
| Tier-3 widgets (DataTable, Tree, DirectoryTree, TextArea, Markdown, RichLog, Log, ProgressBar, Sparkline, Header, Footer) | `widgets/datatable.nim`, `tree.nim`, `directory_tree.nim`, `textarea.nim`, `markdown.nim`, `markdown_viewer.nim`, `rich_log.nim`, `log.nim`, `progress_bar.nim`, `sparkline.nim`, `header.nim`, `footer.nim` | mostly | DataTable virtualisation, Tree lazy expand, RichLog auto-follow all production-ready. **TextArea syntax highlighting** ships only the stub Python/Nim keyword highlighter (M19 spec deferred tree-sitter integration). |
| Workers (background tasks) | `worker/worker.nim`, `worker/manager.nim`, `worker/decorator.nim` | full | Cooperative cancellation, per-harness isolation, `{.work.}` decorator. |
| Command Palette (Provider, fuzzy match) | `command/palette.nim`, `command/fuzzy.nim` | full | Provider system + Sublime-style fuzzy scoring (`test_fuzzy_matcher_corpus.nim`). |
| Snapshot testing (six formats) | `testing/snapshot/*` + harness `snap()` | full | plaintext / ansi / cellmap / svg / annotated-svg / treedump; HTML mismatch report. |
| Pilot / HeadlessDriver (test driver) | `testing/pilot.nim`, `drivers/headless_driver.nim` | full | `press`, `type`, `click`, `hover`, `focus`, `paste`, `waitFor`, `waitForAnimation`, virtual-clock advance. |
| Markdown rendering | `widgets/markdown.nim`, `markdown_viewer.nim` | mostly | CommonMark headings, lists, code blocks, paragraphs, block quotes, links, tables. **Heavyweight extensions** (footnotes, definition lists, task lists with checkbox interaction) are deferred. |
| TextArea (multi-line code editor) | `widgets/textarea.nim` | partial | Soft-wrap + grapheme-aware cursor + undo/redo + read-only + tab size + maxUndoDepth. **Tree-sitter syntax highlighting deferred** (M19 spec); only the stub Python/Nim keyword highlighter ships. |
| DataTable | `widgets/datatable.nim` | full | Virtualisation perf gated by `test_datatable_virtualisation_perf.nim`; sortable cols, selection, snapshot coverage. |
| Image protocols (Kitty, iTerm2, Sixel) | `widgets/image.nim` | mostly | Kitty graphics + protocol fallback (Unicode-block) cover the common cases. **iTerm2 inline-image** + **native Sixel** encoders deferred — the fallback Unicode-block path keeps the widget functional everywhere. |
| Recording / Replay (M25 — IsoNim-specific extension) | `testing/recorder.nim`, `replayer.nim`, `recording_types.nim`, `assertions.nim` | full | Round-trip serialisation, byte-identical replay, time-travel timeline HTML, layout assertions (`assertNoOverlap`, `assertSinglePassPaint`). |
| WebDriver (M26 — IsoNim-specific extension) | `drivers/web_driver.nim` + `isonim-tui-serve` repo | mostly | D/M/P packet driver + WebSocket bridge with xterm.js demo. **Live-browser Playwright e2e** explicitly deferred (test_serve_browser_e2e left open) — bridge correctness is gated by the real-subprocess + real-WebSocket round-trip test. |

## Honest gaps

The biggest deferred items, surfaced explicitly:

1. **TextArea tree-sitter syntax highlighting** (M19). Only stub
   keyword highlighters for Python and Nim. The widget surface is
   stable; swapping in tree-sitter is purely an internal upgrade.
2. **Image iTerm2 + Sixel protocols** (M14). Kitty graphics + Unicode
   fallback ship. The protocol negotiation layer is in place; the two
   encoders are the missing piece.
3. **WebDriver live-browser e2e** (M26). The packet bridge is real
   and tested; what's missing is a Playwright-driven Chromium harness
   asserting full visual parity in a real browser. Gated behind CI
   provisioning that's out of scope for M27.
4. **Markdown extension grammar** (M20). CommonMark core ships;
   Markdown footnotes, task lists with reactive checkbox state, and
   definition lists are deferred.
5. **Some TCSS properties parse-but-no-paint**. The corpus tests in
   `test_css_parse_real_textual_corpus.nim` accept Textual's full
   property grammar; the M11–M21 widgets honour the 12 load-bearing
   properties listed in `docs/tcss-reference.md`. Other properties
   are silently no-ops at paint.

Everything else is at full or mostly-full parity with Textual, gated
by the per-feature tests under `tests/`.
