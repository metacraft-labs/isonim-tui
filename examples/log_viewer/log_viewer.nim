## examples/log_viewer/log_viewer.nim — M27 demo: RichLog tailing a
## bundled sample file.
##
## Demonstrates:
##   * `RichLog` (M21) with auto-follow enabled
##   * Loading content from a local fixture file
##   * Header / Footer chrome
##
## The sample log is bundled as `sample.log` so the demo binary works
## without external state.
##
## DM-M2: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Structural divs use `tdiv(class=...)`,
## widgets compose via the `w*` wrappers in
## `isonim_tui/dsl/widget_blocks`. The RichLog needs the widget
## object (not just its node) to push lines, so it's built outside
## the `ui()` block via `newRichLog` and inserted into the tree via
## a small `mountRichLog` helper that returns its `.node`.

import std/[os, strutils]
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

# ----------------------------------------------------------------------------
# Fixture
# ----------------------------------------------------------------------------

proc samplePath*(): string =
  let here = currentSourcePath().parentDir
  here / "sample.log"

proc readSampleLines*(): seq[string] =
  if fileExists(samplePath()):
    result = readFile(samplePath()).splitLines()
    # Drop a trailing empty newline.
    if result.len > 0 and result[^1].len == 0:
      result.setLen(result.len - 1)
  else:
    result = @[
      "INFO  startup: log_viewer demo",
      "WARN  fixture missing — using inline fallback",
      "INFO  ok"]

# ----------------------------------------------------------------------------
# ViewModel
# ----------------------------------------------------------------------------

type
  LogViewerVM* = ref object
    lines*: seq[string]
    cursor*: int  ## How many lines have been streamed so far.

proc newLogViewerVM*(): LogViewerVM =
  LogViewerVM(lines: readSampleLines(), cursor: 0)

proc streamAll*(vm: LogViewerVM) =
  vm.cursor = vm.lines.len

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc buildRichLogNode(r: TerminalRenderer; vm: LogViewerVM;
                      width, height: int): TerminalNode =
  ## Construct the RichLog widget with all sample lines pre-streamed,
  ## and return its node so the DSL can append it as a child. The
  ## RichLog's `write` API needs the widget object (not just the
  ## node), so construction happens here in a helper rather than
  ## through a DSL wrapper — see the RichLog comment in
  ## `src/isonim_tui/dsl/widget_blocks.nim` for the rationale.
  let body = newRichLog(r, width = width, viewportHeight = height,
                        autoFollow = true, wrap = false,
                        border = bsRound)
  for line in vm.lines:
    body.write(line)
  vm.cursor = vm.lines.len
  body.node

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildLogViewerApp*(h: TerminalTestHarness; vm: LogViewerVM):
                       TerminalNode =
  let r = h.renderer
  let cols = h.cols
  let bodyHeight = max(3, h.rows - 4)
  let footerBindings = @[
    FooterBinding(key: "q",  description: "Quit"),
    FooterBinding(key: "g",  description: "Top"),
    FooterBinding(key: "G",  description: "Bottom"),
    FooterBinding(key: "/",  description: "Search")]

  result = ui(r):
    tdiv(class = "log-viewer"):
      wHeader(r, "Log Viewer", "tail of sample.log", cols)
      buildRichLogNode(r, vm, cols, bodyHeight)
      wFooter(r, footerBindings, cols, true)

proc mountLogViewer*(h: TerminalTestHarness): LogViewerVM =
  let vm = newLogViewerVM()
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildLogViewerApp(h, vm))
  vm

when isMainModule:
  let h = newTerminalTestHarness(80, 20)
  let vm = mountLogViewer(h)
  echo "Log viewer mounted with ", vm.lines.len, " lines."
  h.dispose()
