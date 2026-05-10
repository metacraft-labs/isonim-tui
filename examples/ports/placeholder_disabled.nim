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
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The disabled-band styling (data-disabled
## attribute + dimmed colour) is a setStyle/setAttribute pass on the
## constructed node, which can't be expressed inside the DSL block;
## we build the second placeholder via a small helper outside the
## block (mirrors the "needs the node before mounting" pattern from
## DM-M2's RichLog precedent).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildDisabledPlaceholderNode(r: TerminalRenderer; width, height: int):
                                 TerminalNode =
  ## Construct a placeholder and mark it disabled. The setAttribute /
  ## setStyle calls can't live inside the `ui()` block (they'd need
  ## the node before it's appended), so the whole thing is built
  ## here and returned as a node for the DSL to embed.
  let p = newPlaceholder(r, name = "Placeholder",
                         width = width, height = height)
  # Mark the placeholder as disabled so the snapshot picks up the
  # dimmed-band styling.
  r.setAttribute(p.node, "data-disabled", "true")
  r.setStyle(p.node, "color", "bright_black")
  p.node

proc buildPlaceholderDisabledApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  # `1fr` in a 2-row split → each placeholder gets half the height.
  let halfRows = max(2, h.rows div 2)
  let secondHeight = h.rows - halfRows

  result = ui(r):
    tdiv(class = "placeholder-disabled-port"):
      wPlaceholder(r, "Placeholder", h.cols, halfRows)
      buildDisabledPlaceholderNode(r, h.cols, secondHeight)
