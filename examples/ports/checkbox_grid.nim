## examples/ports/checkbox_grid.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's checkbox-set apps. Four `Checkbox` widgets
## stacked vertically inside a bordered Container, two checked and
## two unchecked, to capture the on/off glyph variants in one frame.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const CheckboxEntries = [
  ("Enable feature A", true),
  ("Enable feature B", false),
  ("Enable feature C", true),
  ("Enable feature D", false)]

proc buildCheckboxStack(r: TerminalRenderer;
                        width, viewportHeight: int): TerminalNode =
  ## Build a bordered vertical `Container` with one `Checkbox` per
  ## entry. Returns the container's `.node` for the DSL to embed.
  let outer = newContainer(r, width = width,
                           viewportHeight = viewportHeight,
                           border = bsSolid, layout = clVertical)
  for (label, value) in CheckboxEntries:
    let cb = newCheckbox(r, label = label, value = value)
    outer.append(cb.node)
  outer.node

proc buildCheckboxGridApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let width = max(20, h.cols - 2)
  let viewportHeight = max(4, h.rows - 2)
  result = ui(r):
    tdiv(class = "checkbox-grid-port"):
      buildCheckboxStack(r, width, viewportHeight)
