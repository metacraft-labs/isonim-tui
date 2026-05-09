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

import isonim_tui

proc buildWelcomeApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let w = newWelcome(r, width = h.cols, height = h.rows)
  r.appendChild(root, w.node)
  root
