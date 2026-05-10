## examples/ports/nested_containers.nim — Nim port (M23 Batch-3).
##
## Demonstrates M11 Container composition: a bordered outer Container
## holding a stack of single-line "row" widgets — the same pattern
## Textual's basic snapshot apps use to anchor the vertical-stack
## render path. M11's vertical Container only consumes one text-row
## per direct child, so we stack borderless single-line children.
##
## DM-M5: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`.

import isonim_tui
import isonim/dsl/ui

const RowLabels = ["row one", "row two", "row three", "row four"]

proc buildNestedStack(r: TerminalRenderer;
                      width, viewportHeight, innerWidth: int): TerminalNode =
  ## Build a bordered vertical `Container` with one borderless `Static`
  ## per row label. Returns the container's `.node` for the DSL to
  ## embed.
  let outer = newContainer(r, width = width,
                           viewportHeight = viewportHeight,
                           border = bsRound, layout = clVertical)
  for label in RowLabels:
    let s = newStatic(r, label, width = innerWidth, height = 1)
    outer.append(s.node)
  outer.node

proc buildNestedContainersApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let width = max(20, h.cols - 4)
  let viewportHeight = max(5, h.rows - 2)
  let innerWidth = max(15, h.cols - 6)
  result = ui(r):
    tdiv(class = "nested-containers-port"):
      buildNestedStack(r, width, viewportHeight, innerWidth)
