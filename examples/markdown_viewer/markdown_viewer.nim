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
  let mdWidth = h.cols - 2
  let mdSource = readmeSource()

  result = ui(r):
    tdiv(class = "markdown-viewer"):
      wMarkdown(r, mdSource, mdWidth, bsRound)

proc mountMarkdownViewer*(h: TerminalTestHarness) =
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildMarkdownViewerApp(h))

when isMainModule:
  let h = newTerminalTestHarness(60, 24)
  mountMarkdownViewer(h)
  echo "Markdown viewer mounted, source = ", readmeSource().len, " chars."
  h.dispose()
