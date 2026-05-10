## examples/ports/rules.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/rules.py` (M23 compat suite).
##
## Original (Python):
##
##   RULE_STYLES = ["ascii", "blank", "dashed", "double", "heavy",
##                  "hidden", "none", "solid", "thick"]
##
##   class RuleApp(App):
##       def compose(self) -> ComposeResult:
##           with Vertical():
##               for rule_style in RULE_STYLES:
##                   yield Rule(line_style=rule_style)
##           with Horizontal():
##               for rule_style in RULE_STYLES:
##                   yield Rule("vertical", line_style=rule_style)
##
## Stacks every supported `Rule` line style horizontally and
## vertically. The M11 `Rule` widget has direct mappings for every
## value in `RULE_STYLES` via the `BorderStyle` enum.
##
## DM-M3: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Each `Container` (top vertical stack,
## bottom horizontal row) needs the widget object to call `.append`,
## so they're built outside the `ui()` block by helper procs that
## return the container's `.node` for the DSL to embed (mirrors
## DM-M2's `log_viewer.buildRichLogNode` precedent).

import isonim_tui
import isonim/dsl/ui

const RuleStyles*: array[9, BorderStyle] = [
  bsAscii, bsBlank, bsDashed, bsDouble, bsHeavy,
  bsHidden, bsNone, bsSolid, bsThick]

proc buildVerticalStack(r: TerminalRenderer; width, viewportHeight: int):
                       TerminalNode =
  ## Top half: every `RuleStyles` entry stamped as a horizontal rule
  ## stacked top-to-bottom inside a vertical container.
  let top = newContainer(r, width = width, viewportHeight = viewportHeight,
                         layout = clVertical)
  for s in RuleStyles:
    let rule = newRule(r, orientation = roHorizontal,
                       width = width, style = s)
    top.append(rule.node)
  top.node

proc buildHorizontalRow(r: TerminalRenderer; width, height: int):
                       TerminalNode =
  ## Bottom half: every `RuleStyles` entry stamped as a vertical rule
  ## placed left-to-right inside a horizontal container.
  let bottom = newContainer(r, width = width,
                            viewportHeight = max(1, height),
                            layout = clHorizontal)
  for s in RuleStyles:
    let rule = newRule(r, orientation = roVertical,
                       height = max(1, height), style = s)
    bottom.append(rule.node)
  bottom.node

proc buildRulesApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let halfRows = max(RuleStyles.len, h.rows div 2)
  let bottomRows = h.rows - halfRows

  result = ui(r):
    tdiv(class = "rules-port"):
      buildVerticalStack(r, h.cols, halfRows)
      buildHorizontalRow(r, h.cols, bottomRows)
