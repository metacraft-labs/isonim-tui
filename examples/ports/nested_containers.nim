## examples/ports/nested_containers.nim — Nim port (M23 Batch-3).
##
## Demonstrates M11 Container composition: a bordered outer Container
## holding a stack of single-line "row" widgets — the same pattern
## Textual's basic snapshot apps use to anchor the vertical-stack
## render path.
##
## Note: M11's vertical Container only consumes one text-row per
## direct child. Nesting another bordered Container inside is a known
## gap (it would lose its top/bottom border rows in the parent). So we
## stack borderless single-line children, which is the surface the
## widget was designed for.

import isonim_tui

proc buildNestedContainersApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let outer = newContainer(r, width = max(20, h.cols - 4),
                           viewportHeight = max(5, h.rows - 2),
                           border = bsRound, layout = clVertical)
  for label in ["row one", "row two", "row three", "row four"]:
    let s = newStatic(r, label, width = max(15, h.cols - 6), height = 1)
    outer.append(s.node)
  r.appendChild(root, outer.node)
  root
