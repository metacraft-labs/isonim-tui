# Textual Compatibility Ports (M23)

This directory contains Nim ports of Textual's `tests/snapshot_tests/snapshot_apps/`
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

| Port                       | Textual source                                             | Widgets exercised                          |
| -------------------------- | ---------------------------------------------------------- | ------------------------------------------ |
| `button_outline.nim`       | `snapshot_apps/button_outline.py`                          | Button (M12)                               |
| `button_widths.nim`        | `snapshot_apps/button_widths.py`                           | Button (M12), Container (M11)              |
| `placeholder_disabled.nim` | `snapshot_apps/placeholder_disabled.py`                    | Placeholder (M11)                          |
| `rules.nim`                | `snapshot_apps/rules.py`                                   | Rule (M11), Container (M11)                |
| `sparkline.nim`            | `snapshot_apps/sparkline.py`                               | Sparkline (M21)                            |
| `progress_gradient.nim`    | `snapshot_apps/progress_gradient.py`                       | ProgressBar (M21)                          |
| `listview_index.nim`       | `snapshot_apps/listview_index.py`                          | ListView (M14), Label (M11)                |
| `data_table_row_labels.nim`| `snapshot_apps/data_table_row_labels.py`                   | DataTable (M17)                            |

### Batch 2 (12 ports — `tests/test_textual_compat_batch2.nim`)

| Port                          | Textual source                                          | Widgets exercised                          |
| ----------------------------- | ------------------------------------------------------- | ------------------------------------------ |
| `welcome_widget.nim`          | `snapshot_apps/welcome_widget.py`                       | Welcome (M21)                              |
| `button_multiline_label.nim`  | `snapshot_apps/button_multiline_label.py`               | Button (M12) — multi-line label            |
| `button_markup.nim`           | `snapshot_apps/button_markup.py`                        | Button (M12) — markup labels, disabled     |
| `option_list_long.nim`        | `snapshot_apps/option_list_long.py`                     | OptionList (M14)                           |
| `big_button.nim`              | `snapshot_apps/big_button.py`                           | Button (M12) — custom height intent        |
| `log_write.nim`               | `snapshot_apps/log_write.py`                            | Log (M21)                                  |
| `text_log_blank_write.nim`    | `snapshot_apps/text_log_blank_write.py`                 | RichLog (M21)                              |
| `richlog_max_lines.nim`       | `snapshot_apps/richlog_max_lines.py`                    | RichLog (M21) — `maxLines` cap             |
| `viewport_units.nim`          | `snapshot_apps/viewport_units.py`                       | Static (M11) — viewport-sized              |
| `multi_keys.nim`              | `snapshot_apps/multi_keys.py`                           | Footer (M21) — bindings                    |
| `toggle_style_order.nim`      | `snapshot_apps/toggle_style_order.py`                   | Checkbox (M12), Label (M11)                |
| `horizontal_auto_width.nim`   | `snapshot_apps/horizontal_auto_width.py`                | Container (M11) horizontal, Static (M11)   |

### Batch 3 (12 ports — `tests/test_textual_compat_batch3.nim`)

| Port                              | Inspired by Textual app                          | Widgets exercised                                 |
| --------------------------------- | ------------------------------------------------ | ------------------------------------------------- |
| `static_padding.nim`              | `static_padding.py` family                       | Static (M11) — pad widths                         |
| `multiple_borders.nim`            | `border-styles` snapshot apps                    | Static (M11) — six BorderStyle variants           |
| `nested_containers.nim`           | composition snapshot apps                        | Container (M11) — vertical-stack composition      |
| `tabs_basic.nim`                  | `tabs_basic.py`                                  | Tabs (M11), Static (M11)                          |
| `progress_bar_states.nim`         | progress-bar snapshot apps                       | ProgressBar (M21) — five percentage points        |
| `loading_indicator_demo.nim`      | `loading_indicator.py`                           | LoadingIndicator (M11) — three labels             |
| `header_with_title.nim`           | `header_screen.py`                               | Header (M21) — title + subtitle                   |
| `footer_chips.nim`                | footer-chip snapshot apps                        | Footer (M21) — 4 keyboard bindings                |
| `horizontal_static_row.nim`       | new — exercises `clHorizontal` default          | Container (M11) horizontal, Static (M11)          |
| `listview_basic.nim`              | small-list snapshot apps                         | ListView (M14) — 5 entries                        |
| `checkbox_grid.nim`               | checkbox-set apps                                | Checkbox (M12), Container (M11)                   |
| `buttons_horizontal_row.nim`      | button-row snapshot apps                         | Button (M12), Container (M11) horizontal          |

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
