## examples/ports/text_log_blank_write.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/text_log_blank_write.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class RichLogApp(App):
##       def compose(self) -> ComposeResult:
##           yield RichLog()
##       def on_mount(self) -> None:
##           tl = self.query_one(RichLog)
##           tl.write("Hello")
##           tl.write("")
##           tl.write("World")
##
## A RichLog with three writes, one of which is empty. The blank
## entry should still consume a row in the rendered widget.
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The `RichLog` widget needs the widget object
## to call `rl.write(line)` after construction, so it's built outside
## the `ui()` block and embedded via `embedNode` (mirrors DM-M2's
## `log_viewer.buildRichLogNode` precedent).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildTextLogBlankWriteApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer

  let rl = newRichLog(r,
                      width = max(20, h.cols - 2),
                      viewportHeight = max(4, h.rows - 2),
                      border = bsSolid)
  rl.write("Hello")
  rl.write("")
  rl.write("World")

  result = ui(r):
    tdiv(class = "text-log-blank-write-port"):
      embedNode(rl.node)
