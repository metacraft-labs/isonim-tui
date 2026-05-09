## examples/ports/checkbox_grid.nim — Nim port (M23 Batch-3).
##
## Inspired by Textual's checkbox-set apps. Stacks four `Checkbox`
## widgets vertically inside a bordered Container, two checked and
## two unchecked, to capture the on/off glyph variants in one frame.

import isonim_tui

proc buildCheckboxGridApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let outer = newContainer(r,
    width = max(20, h.cols - 2), viewportHeight = max(4, h.rows - 2),
    border = bsSolid, layout = clVertical)
  let entries = [
    ("Enable feature A", true),
    ("Enable feature B", false),
    ("Enable feature C", true),
    ("Enable feature D", false)]
  for (label, value) in entries:
    let cb = newCheckbox(r, label = label, value = value)
    outer.append(cb.node)
  r.appendChild(root, outer.node)
  root
