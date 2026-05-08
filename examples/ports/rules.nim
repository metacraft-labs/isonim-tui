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

import isonim_tui

const RuleStyles*: array[9, BorderStyle] = [
  bsAscii, bsBlank, bsDashed, bsDouble, bsHeavy,
  bsHidden, bsNone, bsSolid, bsThick]

proc buildRulesApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  # Two-up vertical layout: top half horizontal-rule stack, bottom half
  # horizontal-row of vertical rules.
  let halfRows = max(RuleStyles.len, h.rows div 2)
  let topWidth = h.cols
  let top = newContainer(r, width = topWidth, viewportHeight = halfRows,
                         layout = clVertical)
  for s in RuleStyles:
    let rule = newRule(r, orientation = roHorizontal,
                       width = topWidth, style = s)
    top.append(rule.node)
  r.appendChild(root, top.node)

  let bottomRows = h.rows - halfRows
  let bottom = newContainer(r, width = h.cols,
                            viewportHeight = max(1, bottomRows),
                            layout = clHorizontal)
  for s in RuleStyles:
    let rule = newRule(r, orientation = roVertical,
                       height = max(1, bottomRows), style = s)
    bottom.append(rule.node)
  r.appendChild(root, bottom.node)

  root
