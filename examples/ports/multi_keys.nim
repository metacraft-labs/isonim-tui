## examples/ports/multi_keys.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/multi_keys.py` (M23 compat suite).
##
## Original (Python):
##
##   class MApp(App):
##       BINDINGS = [Binding("o,ctrl+o", "options", "Options")]
##       def compose(self) -> ComposeResult:
##           yield Footer()
##
## A Footer that surfaces a single binding which has two equivalent
## key triggers (`o` or `ctrl+o`). Textual collapses the multi-key
## binding into one row whose `[ key ]` chip shows the primary key.
## isonim-tui's M21 Footer takes pre-formed `FooterBinding` records;
## we render the same primary key chip + description so the
## cell-content lines up.

import isonim_tui

proc buildMultiKeysApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let f = newFooter(r,
                    bindings = @[
                      FooterBinding(key: "o",
                                    description: "Options",
                                    disabled: false)],
                    width = h.cols)
  r.appendChild(root, f.node)
  root
