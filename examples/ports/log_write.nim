## examples/ports/log_write.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/log_write.py` (M23 compat suite).
##
## Original (Python):
##
##   class LogApp(App):
##       def compose(self) -> ComposeResult:
##           yield Log()
##       def on_ready(self) -> None:
##           log = self.query_one(Log)
##           log.write("Hello,")
##           log.write(" World")
##           log.write("!\nWhat's up?")
##           log.write("")
##           log.write("\n")
##           log.write("FOO")
##
## A single `Log` widget driven through a fixed write sequence —
## including blanks and a literal `\n` — that exercises the M21
## widget's append + line-split pipeline.

import isonim_tui

proc buildLogWriteApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let lg = newLog(r,
                  width = max(20, h.cols - 2),
                  viewportHeight = max(4, h.rows - 2),
                  border = bsSolid)
  r.appendChild(root, lg.node)

  # Replicate the on_ready writes verbatim.
  lg.write("Hello,")
  lg.write(" World")
  lg.write("!\nWhat's up?")
  lg.write("")
  lg.write("\n")
  lg.write("FOO")
  root
