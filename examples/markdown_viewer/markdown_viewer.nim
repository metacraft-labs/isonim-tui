## examples/markdown_viewer/markdown_viewer.nim — M27 demo: Markdown
## widget rendering a bundled README.
##
## Demonstrates:
##   * `Markdown` (M20) parsing CommonMark
##   * Loading content from a small bundled `README.md`
##
## Bundling a tiny README keeps the demo self-contained. The Markdown
## widget consumes the file at mount time; subsequent edits to the
## fixture won't propagate without remounting.

import std/os
import isonim_tui

# ----------------------------------------------------------------------------
# Fixture
# ----------------------------------------------------------------------------

const FallbackReadme = """
# IsoNim-TUI Markdown demo

This is a fallback README rendered when the bundled `README.md`
fixture is missing.

## Features

- Heading, lists, code blocks
- Paragraphs with **bold** and *italic*
- Inline `code` spans

```nim
echo "Hello, IsoNim-TUI!"
```

> A block quote, for completeness.
"""

proc readmePath*(): string =
  let here = currentSourcePath().parentDir
  here / "README.md"

proc readmeSource*(): string =
  if fileExists(readmePath()):
    try: result = readFile(readmePath())
    except IOError: result = FallbackReadme
  else:
    result = FallbackReadme

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildMarkdownViewerApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.setAttribute(root, "class", "markdown-viewer")

  let md = newMarkdown(r, source = readmeSource(),
                       width = h.cols - 2,
                       border = bsRound)
  r.appendChild(root, md.node)
  root

proc mountMarkdownViewer*(h: TerminalTestHarness) =
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildMarkdownViewerApp(h))

when isMainModule:
  let h = newTerminalTestHarness(60, 24)
  mountMarkdownViewer(h)
  echo "Markdown viewer mounted, source = ", readmeSource().len, " chars."
  h.dispose()
