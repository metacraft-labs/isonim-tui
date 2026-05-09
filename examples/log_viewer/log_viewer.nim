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

import std/[os, strutils]
import isonim_tui

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
# Composition
# ----------------------------------------------------------------------------

proc buildLogViewerApp*(h: TerminalTestHarness; vm: LogViewerVM):
                       TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.setAttribute(root, "class", "log-viewer")

  # Header row.
  let header = newHeader(r, title = "Log Viewer",
                         subtitle = "tail of sample.log",
                         width = h.cols)
  r.appendChild(root, header.node)

  # RichLog body — auto-follow on so the most recent line stays
  # visible.
  let body = newRichLog(r, width = h.cols,
                        viewportHeight = max(3, h.rows - 4),
                        autoFollow = true,
                        wrap = false,
                        border = bsRound)
  r.appendChild(root, body.node)
  for line in vm.lines:
    body.write(line)
  vm.cursor = vm.lines.len

  # Footer with bindings.
  let footer = newFooter(r,
    bindings = @[
      FooterBinding(key: "q",  description: "Quit"),
      FooterBinding(key: "g",  description: "Top"),
      FooterBinding(key: "G",  description: "Bottom"),
      FooterBinding(key: "/",  description: "Search")],
    width = h.cols, compact = true)
  r.appendChild(root, footer.node)

  root

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
