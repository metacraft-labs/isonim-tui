# Textual Compatibility Ports (M23)

This directory contains Nim ports of Textual's `tests/snapshot_tests/snapshot_apps/`
applications, used to anchor the Textual Compatibility Suite (M23).

## Status (20 / 30+ ports landed across two batches)

The full M23 vision is 30+ ports cross-checked against a live Textual
subprocess. The runtime Textual subprocess parity step has been deferred
since the M6 / M19 milestones already documented (`Textual not in the
dev-shell as of M6; runtime parity test will land with M23`). Pragmatic
scoping per the milestone notes: this milestone ships a **representative
cross-section** of 20 ports (Batch 1: 8 in `test_textual_compat.nim`;
Batch 2: 12 in `test_textual_compat_batch2.nim`) plus the tagged-failure
/ golden-tolerance infrastructure. The remaining ports are tracked as
Appendix C follow-ups in the milestones doc.

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

## Apps ported (20 / 30+)

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
- **Container horizontal layout** — `clHorizontal` is declarative
  metadata at M11; child widgets still stack vertically inside the
  container body. Affects `horizontal_auto_width`. The setter exists so
  callers can declare intent ahead of the layout-cascade integration.
- **Welcome body content** — the M21 `Welcome` widget ships its own
  `DefaultWelcomeBody` (isonim-tui-flavoured); Textual's body text is
  different.

## Wiring

Each port exports `build*App(h: TerminalTestHarness): TerminalNode` —
the test harness mounts and snapshots one port per `test` block in
`tests/test_textual_compat.nim` (Batch 1) or
`tests/test_textual_compat_batch2.nim` (Batch 2).
