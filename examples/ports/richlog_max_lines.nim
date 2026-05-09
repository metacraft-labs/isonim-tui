## examples/ports/richlog_max_lines.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/richlog_max_lines.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class RichLogLines(App):
##       count = 0
##       def compose(self):
##           yield RichLog(max_lines=3)
##       async def on_key(self):
##           self.count += 1
##           log_widget = self.query_one(RichLog)
##           log_widget.write(f"Key press #{self.count}")
##
## A RichLog with a 3-line cap, driven by 5 simulated key presses.
## After the 5th write only the last 3 entries should be visible —
## confirming the M21 widget enforces `maxLines`.

import isonim_tui

proc buildRichLogMaxLinesApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let rl = newRichLog(r,
                      width = max(20, h.cols - 2),
                      viewportHeight = max(4, h.rows - 2),
                      maxLines = 3,
                      border = bsSolid)
  r.appendChild(root, rl.node)

  for i in 1 .. 5:
    rl.write("Key press #" & $i)
  root
