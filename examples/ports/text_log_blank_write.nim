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

import isonim_tui

proc buildTextLogBlankWriteApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let rl = newRichLog(r,
                      width = max(20, h.cols - 2),
                      viewportHeight = max(4, h.rows - 2),
                      border = bsSolid)
  r.appendChild(root, rl.node)

  rl.write("Hello")
  rl.write("")
  rl.write("World")
  root
