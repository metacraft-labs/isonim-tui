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

import std/os
import isonim_tui

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
  let root = r.createElement("div")
  r.setAttribute(root, "class", "code-browser")

  let halfWidth = max(20, h.cols div 2 - 1)

  # Left pane: directory tree.
  let dt = newDirectoryTree(r, path = fixtureRoot(),
                            width = halfWidth,
                            viewportHeight = h.rows - 2,
                            border = bsRound)
  r.appendChild(root, dt.node)

  # Right pane: textarea.
  let ta = newTextArea(r, text = vm.content,
                       width = h.cols - halfWidth - 2,
                       viewportHeight = h.rows - 2,
                       border = bsRound,
                       readOnly = true)
  r.appendChild(root, ta.node)

  root

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
