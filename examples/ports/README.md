# Textual Compatibility Ports (M23)

This directory contains Nim ports of Textual's `tests/snapshot_tests/snapshot_apps/`
applications, used to anchor the Textual Compatibility Suite (M23).

## Status (scoped from 30+ apps to 8 representative ports)

The full M23 vision is 30+ ports cross-checked against a live Textual
subprocess. The runtime Textual subprocess parity step has been deferred
since the M6 / M19 milestones already documented (`Textual not in the
dev-shell as of M6; runtime parity test will land with M23`). Pragmatic
scoping per the milestone notes: this milestone ships a **representative
cross-section** of 8 ports plus the tagged-failure / golden-tolerance
infrastructure. The remaining 22+ ports are tracked as Appendix C
follow-ups in the milestones doc.

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

## Apps ported (8 / 30+)

Source files live one per app under this directory; the corresponding
Textual originals are noted below.

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

## Wiring

Each port exports `build*App(h: TerminalTestHarness): TerminalNode` —
the test harness mounts and snapshots one port per `test` block in
`tests/test_textual_compat.nim`.
