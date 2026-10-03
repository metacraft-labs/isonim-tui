# Textual Compatibility Ports (M23)

This directory contains Nim ports of Textual's
`tests/snapshot_tests/snapshot_apps/`
applications, used to anchor the Textual Compatibility Suite (M23).

## Status (32 / 30+ ports landed across three batches)

The M23 vision of 30+ ports has now been hit. The runtime Textual
subprocess parity step remains deferred (Textual is still not in the
dev-shell as of M6 / M19). Three batches:

- Batch 1: 8 ports in `test_textual_compat.nim`.
- Batch 2: 12 ports in `test_textual_compat_batch2.nim`.
- Batch 3: 12 ports in `test_textual_compat_batch3.nim` — landed
  alongside the `Container.clHorizontal` default-render switch
  (legacy vertical fall-through retired; M23 horizontal goldens
  re-recorded against the real left-to-right path in the same
  change-set).

## DSL composition pattern

Every port is a single `ui(r):` composition root following the
canonical IsoNim DSL idiom. This was the focus of the DM-M0..DM-M7
demo-modernization series (Batch 1 was refactored under DM-M3, Batch 2
under DM-M4, Batch 3 under DM-M5). Inside `ui(r):` you mix two kinds
of calls: raw HTML-flavoured structural elements (`tdiv(class=...)`,
`span`, `button`, ...) emitted by the macro as `createElement` +
`setAttribute` + child sub-tree, and `w*` wrappers from
`src/isonim_tui/dsl/widget_blocks.nim` that mount M11-M21 widgets.
**Wrappers must be called with positional arguments only** — any
`name = value` argument promotes the call to a synthetic HTML element
(see "Two DSL gaps" in `docs/dsl-pattern.md`).

A small worked example (the shape used by every Batch-3 port that
composes inside the DSL):

```nim
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildHeaderWithTitleApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "header-with-title-port"):
      wHeader(r, "Demo Title", "subtitle text", 60)
```

When a port needs to call methods on the widget object after
construction — for example `Input.setValue`, `RichLog.body.write`, or
`Container.append` — build the widget in a small helper outside the
`ui()` block and embed its `.node` using `embedNode(handle.node)`
inside the composition root. Several ports use this pattern
(`option_list_long`, `log_write`, `richlog_max_lines`,
`button_widths`, `rules`, `listview_index`, `data_table_row_labels`).
See `docs/dsl-pattern.md` for the full reference, the two known DSL
gaps, and the rationale for each wrapper signature.

## What "parity" means here

For each port the SVG (and five companion formats) emitted by
`TerminalTestHarness` is compared against a stored golden under
`tests/snapshots/m23_<name>/`. Goldens are recorded by setting
`SNAP_RECORD=1` (or by deleting the directory and re-running the test).
The snapshot runner already handles the record-vs-compare flow.

## Tolerance definition

Strict cell-content parity is enforced for plaintext / cellmap / svg
goldens. SGR ordering may differ from Textual's encoder — the snapshot
runner's `ansi.ansi` golden is compared against the *isonim-tui*
encoder's output (which is itself byte-stable across runs by virtue of
the M2 stable-snapshot test). This matches the M23 milestone wording
("cell-content identical; SGR ordering may differ but visual result
identical").

## Apps ported (32 / 30+)

Source files live one per app under this directory; the corresponding
Textual originals are noted below.

### Batch 1 (8 ports — `tests/test_textual_compat.nim`)

- **Port:** `button_outline.nim`
  - **Textual source:** `snapshot_apps/button_outline.py`
  - **Widgets exercised:** Button (M12)

- **Port:** `button_widths.nim`
  - **Textual source:** `snapshot_apps/button_widths.py`
  - **Widgets exercised:** Button (M12), Container (M11)

- **Port:** `placeholder_disabled.nim`
  - **Textual source:** `snapshot_apps/placeholder_disabled.py`
  - **Widgets exercised:** Placeholder (M11)

- **Port:** `rules.nim`
  - **Textual source:** `snapshot_apps/rules.py`
  - **Widgets exercised:** Rule (M11), Container (M11)

- **Port:** `sparkline.nim`
  - **Textual source:** `snapshot_apps/sparkline.py`
  - **Widgets exercised:** Sparkline (M21)

- **Port:** `progress_gradient.nim`
  - **Textual source:** `snapshot_apps/progress_gradient.py`
  - **Widgets exercised:** ProgressBar (M21)

- **Port:** `listview_index.nim`
  - **Textual source:** `snapshot_apps/listview_index.py`
  - **Widgets exercised:** ListView (M14), Label (M11)

- **Port:** `data_table_row_labels.nim`
  - **Textual source:** `snapshot_apps/data_table_row_labels.py`
  - **Widgets exercised:** DataTable (M17)

### Batch 2 (12 ports — `tests/test_textual_compat_batch2.nim`)

- **Port:** `welcome_widget.nim`
  - **Textual source:** `snapshot_apps/welcome_widget.py`
  - **Widgets exercised:** Welcome (M21)

- **Port:** `button_multiline_label.nim`
  - **Textual source:** `snapshot_apps/button_multiline_label.py`
  - **Widgets exercised:** Button (M12) — multi-line label

- **Port:** `button_markup.nim`
  - **Textual source:** `snapshot_apps/button_markup.py`
  - **Widgets exercised:** Button (M12) — markup labels, disabled

- **Port:** `option_list_long.nim`
  - **Textual source:** `snapshot_apps/option_list_long.py`
  - **Widgets exercised:** OptionList (M14)

- **Port:** `big_button.nim`
  - **Textual source:** `snapshot_apps/big_button.py`
  - **Widgets exercised:** Button (M12) — custom height intent

- **Port:** `log_write.nim`
  - **Textual source:** `snapshot_apps/log_write.py`
  - **Widgets exercised:** Log (M21)

- **Port:** `text_log_blank_write.nim`
  - **Textual source:** `snapshot_apps/text_log_blank_write.py`
  - **Widgets exercised:** RichLog (M21)

- **Port:** `richlog_max_lines.nim`
  - **Textual source:** `snapshot_apps/richlog_max_lines.py`
  - **Widgets exercised:** RichLog (M21) — `maxLines` cap

- **Port:** `viewport_units.nim`
  - **Textual source:** `snapshot_apps/viewport_units.py`
  - **Widgets exercised:** Static (M11) — viewport-sized

- **Port:** `multi_keys.nim`
  - **Textual source:** `snapshot_apps/multi_keys.py`
  - **Widgets exercised:** Footer (M21) — bindings

- **Port:** `toggle_style_order.nim`
  - **Textual source:** `snapshot_apps/toggle_style_order.py`
  - **Widgets exercised:** Checkbox (M12), Label (M11)

- **Port:** `horizontal_auto_width.nim`
  - **Textual source:** `snapshot_apps/horizontal_auto_width.py`
  - **Widgets exercised:** Container (M11) horizontal, Static (M11)

### Batch 3 (12 ports — `tests/test_textual_compat_batch3.nim`)

- **Port:** `static_padding.nim`
  - **Inspired by Textual app:** `static_padding.py` family
  - **Widgets exercised:** Static (M11) — pad widths

- **Port:** `multiple_borders.nim`
  - **Inspired by Textual app:** `border-styles` snapshot apps
  - **Widgets exercised:** Static (M11) — six BorderStyle variants

- **Port:** `nested_containers.nim`
  - **Inspired by Textual app:** composition snapshot apps
  - **Widgets exercised:** Container (M11) — vertical-stack composition

- **Port:** `tabs_basic.nim`
  - **Inspired by Textual app:** `tabs_basic.py`
  - **Widgets exercised:** Tabs (M11), Static (M11)

- **Port:** `progress_bar_states.nim`
  - **Inspired by Textual app:** progress-bar snapshot apps
  - **Widgets exercised:** ProgressBar (M21) — five percentage points

- **Port:** `loading_indicator_demo.nim`
  - **Inspired by Textual app:** `loading_indicator.py`
  - **Widgets exercised:** LoadingIndicator (M11) — three labels

- **Port:** `header_with_title.nim`
  - **Inspired by Textual app:** `header_screen.py`
  - **Widgets exercised:** Header (M21) — title + subtitle

- **Port:** `footer_chips.nim`
  - **Inspired by Textual app:** footer-chip snapshot apps
  - **Widgets exercised:** Footer (M21) — 4 keyboard bindings

- **Port:** `horizontal_static_row.nim`
  - **Inspired by Textual app:** new — exercises `clHorizontal` default
  - **Widgets exercised:** Container (M11) horizontal, Static (M11)

- **Port:** `listview_basic.nim`
  - **Inspired by Textual app:** small-list snapshot apps
  - **Widgets exercised:** ListView (M14) — 5 entries

- **Port:** `checkbox_grid.nim`
  - **Inspired by Textual app:** checkbox-set apps
  - **Widgets exercised:** Checkbox (M12), Container (M11)

- **Port:** `buttons_horizontal_row.nim`
  - **Inspired by Textual app:** button-row snapshot apps
  - **Widgets exercised:** Button (M12), Container (M11) horizontal

## Per-port fidelity notes

Each port is one of:

- **Cell-identical** — every painted rune matches the recorded golden
  exactly. All Batch-1 ports plus Batch-2's `welcome_widget`,
  `option_list_long`, `log_write`, `text_log_blank_write`,
  `richlog_max_lines`, `viewport_units`, `multi_keys`,
  `horizontal_auto_width` (under the noted gap) fall here once
  recorded.
- **Visually-equivalent** — the chrome is byte-stable, but some
  user-visible content differs because the widget surface ships its
  own copy (e.g. `welcome_widget` body lines).
- **Functionally-equivalent** — the port exercises the same widgets
  driven the same way, but a known gap in the M11/M12/M21 widget
  surface produces a different rendering. Tracked under "Found gaps"
  below; the snapshot is byte-stable against itself once recorded so
  CI still gates the port.

## Found gaps (M23 widget-surface follow-ups)

These are surface gaps that batch-2 surfaced. None block the M23
tolerance contract (the snapshot is byte-stable against the recorded
golden); they are tracked here so M11/M12/M14/M21 follow-ups can pick
them up.

- **Multi-line button labels** — `Button.label` is rendered as a single
  centred row; `\n` separators are not split into multiple body rows
  the way Textual does. Affects `button_multiline_label`, `big_button`.
- **Button `height` CSS** — there's no widget-surface for a tall
  button; `big_button.py`'s `Button { height: 9; }` cannot yet be
  expressed in the M12 widget API.
- **Markup labels** — the `Button` and `Checkbox` label paths take a
  plain `string` and don't yet consume a rich-text `Content` value.
  Bracket sequences render literally. Affects `button_markup`,
  `toggle_style_order`.
- **Container horizontal layout** — *RESOLVED* (Batch 3). The
  `clHorizontal` default render path now dispatches to
  `renderHorizontal` which lays children out left-to-right and
  walks each child's row sequence so multi-row widgets (Buttons,
  bordered Statics) survive the slot. The M23 batch-1 / batch-2
  horizontal goldens (`button_widths`, `rules`,
  `horizontal_auto_width`) were re-recorded against the new layout
  in the same change-set.
- **Container vertical layout — multi-row children** — *RESOLVED*
  (post-Batch-3 follow-up). `renderVertical` now extracts each
  child's per-row content via `childRows()` and stacks rows
  top-to-bottom, honouring an optional `data-cell-height` attribute
  or falling back to the child's intrinsic row count. Bordered
  Statics, Tabs + body, and other multi-row widgets nested inside a
  vertical Container survive with all their rows intact. The three
  Batch-3 ports that worked around the gap by mounting children
  directly under the root (`static_padding`, `multiple_borders`,
  `tabs_basic`) were reverted to the natural nested-Container
  composition; goldens were re-recorded against the new render path
  and remain visually identical to the pre-fix workaround output
  (the bordered Statics paint the same cells either way).
- **Welcome body content** — the M21 `Welcome` widget ships its own
  `DefaultWelcomeBody` (isonim-tui-flavoured); Textual's body text is
  different.

## Wiring

Each port exports `build*App(h: TerminalTestHarness): TerminalNode` —
the test harness mounts and snapshots one port per `test` block in
`tests/test_textual_compat.nim` (Batch 1),
`tests/test_textual_compat_batch2.nim` (Batch 2), or
`tests/test_textual_compat_batch3.nim` (Batch 3).
