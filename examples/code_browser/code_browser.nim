## examples/code_browser/code_browser.nim — M27 demo: DirectoryTree
## paired with TextArea showing file contents.
##
## Demonstrates:
##   * `DirectoryTree` (M18) reading a real on-disk path
##   * `TextArea` (M19) displaying plain text (no syntax highlighting —
##     M19's tree-sitter integration was deferred; plain text is the
##     contract).
##
## The example bundles a small fixture directory (`fixtures/`) so the
## binary works without network or external state. The selection
## handler isn't wired into the textarea here — keeping the bundle
## simple matters more for the snapshot test.
##
## DM-M2: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Structural divs use `tdiv(class=...)`,
## widgets compose via the `w*` wrappers in
## `isonim_tui/dsl/widget_blocks`.

import std/os
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

# ----------------------------------------------------------------------------
# Fixture path resolution. The example dir contains a bundled `fixtures/`
# tree we point the DirectoryTree at; falling back to the example dir
# itself if the fixture isn't present.
# ----------------------------------------------------------------------------

proc fixtureRoot*(): string =
  let here = currentSourcePath().parentDir
  let fx = here / "fixtures"
  if dirExists(fx): fx else: here

# ----------------------------------------------------------------------------
# ViewModel — minimal state: the current selection's content.
# ----------------------------------------------------------------------------

type
  CodeBrowserVM* = ref object
    selectedPath*: string
    content*: string

proc newCodeBrowserVM*(): CodeBrowserVM =
  let root = fixtureRoot()
  # Pick the first file we find for an initial display.
  var initial = ""
  var initialPath = ""
  for kind, path in walkDir(root):
    if kind == pcFile:
      initialPath = path
      try:
        initial = readFile(path)
      except IOError:
        initial = "(unreadable)"
      break
  CodeBrowserVM(selectedPath: initialPath, content: initial)

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildCodeBrowserApp*(h: TerminalTestHarness; vm: CodeBrowserVM):
                         TerminalNode =
  let r = h.renderer
  let halfWidth = max(20, h.cols div 2 - 1)
  let viewport = h.rows - 2
  let textWidth = h.cols - halfWidth - 2
  let treePath = fixtureRoot()
  let textBody = vm.content

  result = ui(r):
    tdiv(class = "code-browser"):
      wDirectoryTree(r, treePath, halfWidth, viewport, bsRound)
      wTextArea(r, textBody, textWidth, viewport, bsRound, true)

proc mountCodeBrowser*(h: TerminalTestHarness): CodeBrowserVM =
  let vm = newCodeBrowserVM()
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildCodeBrowserApp(h, vm))
  vm

when isMainModule:
  let h = newTerminalTestHarness(80, 20)
  let vm = mountCodeBrowser(h)
  echo "Code browser mounted, fixture = ", fixtureRoot()
  echo "Selected: ", vm.selectedPath
  echo "Content length: ", vm.content.len
  h.dispose()
