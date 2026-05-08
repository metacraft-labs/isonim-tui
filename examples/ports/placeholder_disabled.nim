## examples/ports/placeholder_disabled.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/placeholder_disabled.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class DisabledPlaceholderApp(App[None]):
##       CSS = """
##       Placeholder {
##           height: 1fr;
##       }
##       """
##       def compose(self) -> ComposeResult:
##           yield Placeholder()
##           yield Placeholder(disabled=True)
##
## Two stacked placeholders — the second is `disabled=true`. Textual
## paints disabled widgets with a dimmed band; isonim-tui's M11
## placeholder maps the same intent through the standard widget
## lifecycle.

import isonim_tui

proc buildPlaceholderDisabledApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  # `1fr` in a 2-row split → each placeholder gets half the height.
  let halfRows = max(2, h.rows div 2)

  let p1 = newPlaceholder(r, name = "Placeholder",
                          width = h.cols, height = halfRows)
  r.appendChild(root, p1.node)

  let p2 = newPlaceholder(r, name = "Placeholder",
                          width = h.cols, height = h.rows - halfRows)
  # Mark the second placeholder as disabled so the snapshot picks up
  # the dimmed-band styling.
  r.setAttribute(p2.node, "data-disabled", "true")
  r.setStyle(p2.node, "color", "bright_black")
  r.appendChild(root, p2.node)

  root
