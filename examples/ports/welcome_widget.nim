## examples/ports/welcome_widget.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/welcome_widget.py` (M23 compat suite).
##
## Original (Python):
##
##   class WelcomeApp(App[None]):
##       def compose(self) -> ComposeResult:
##           yield Welcome()
##
## A bare `Welcome` widget, exercised at the harness's full viewport.
## The M21 `Welcome` widget paints the rounded-border frame with a
## centred title, body, and action affordance; the default body is
## isonim-tui-flavoured (`DefaultWelcomeBody`) so the snapshot is
## visually-equivalent to Textual's `Welcome()` rather than
## byte-identical.
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The Welcome widget renders entirely from its
## constructor inputs, so the new `wWelcome` wrapper composes cleanly
## inside the DSL block (no need to retain the widget object).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildWelcomeApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  result = ui(r):
    tdiv(class = "welcome-widget-port"):
      wWelcome(r, "Welcome", DefaultWelcomeBody, h.cols, h.rows,
               "OK", "", "")
