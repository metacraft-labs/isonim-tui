## test_markdown_renders_textual_readme — M20 mandatory test.
##
## Render Textual's `README.md` verbatim through the M20 Markdown
## widget. The output structure (headings / paragraphs / code blocks /
## thematic breaks) must match a hand-curated golden derived from the
## upstream README.
##
## The README lives at `../isonim/refs/textual/README.md` (the
## sibling-repo reference checkout). The test is skipped when that
## file is missing — sibling-repo presence is a `repo`-managed concern,
## not a test pre-condition.

import os
import unittest

import isonim_tui

# ----------------------------------------------------------------------------
# Hand-curated golden — derived from the README at the time M20 landed.
# Records the *structure* of the document, not the prose: every block's
# kind (and, for headings, the level + anchor) is recorded in document
# order. The golden is recomputed from the README after structural
# changes; the value asserts are spot checks on the load-bearing
# nodes (the ATX headings) plus block-count totals.
# ----------------------------------------------------------------------------

type
  GoldenHeading = tuple[level: int; anchor: string]

const TextualReadmeHeadings: seq[GoldenHeading] = @[
  (1, "textual"),
  (2, "widgets"),
  (2, "installing"),
  (2, "demo"),
  (2, "dev-console"),
  (2, "command-palette"),
  (1, "textual-web"),
  (2, "join-us-on-discord"),
]

# The README contains (at the time this golden was written) at least
# this many paragraph blocks and code blocks. Use `>=` for forward
# compatibility — small additions to the README shouldn't break the
# test, only structural removals.
const MinParagraphs = 8
const MinCodeBlocks = 3

# ----------------------------------------------------------------------------
# Minimal CommonMark coverage tests. These run unconditionally so the
# parser is exercised even when the upstream README isn't available.
# ----------------------------------------------------------------------------

suite "M20: Markdown widget core (CommonMark essentials)":

  test "headings_paragraphs_lists_codeblocks_hr":
    let source = """
# Top heading

A paragraph with **bold** and *italic* and `inline code`.

## Sub heading

- bullet one
- bullet two
- bullet three

```python
def foo():
    return 42
```

---

> A block quote with **emphasis** inside.

1. ordered first
2. ordered second
"""
    let doc = parseMarkdown(source)
    # Block-level structure: heading, blank, paragraph, blank, heading,
    # blank, list, blank, code-block, blank, hr, blank, quote, blank,
    # ordered-list.
    let nonBlank = block:
      var ks: seq[MdBlockKind] = @[]
      for b in doc.blocks:
        if b.kind != mbBlank: ks.add b.kind
      ks
    check nonBlank.len == 8
    check nonBlank[0] == mbHeading
    check nonBlank[1] == mbParagraph
    check nonBlank[2] == mbHeading
    check nonBlank[3] == mbList
    check nonBlank[4] == mbCodeBlock
    check nonBlank[5] == mbHr
    check nonBlank[6] == mbQuote
    check nonBlank[7] == mbList
    # Heading details.
    check doc.blocks[0].level == 1
    check doc.blocks[0].anchor == "top-heading"
    # The fenced code block carries its info string + content.
    var codeBlock: MdBlock
    for b in doc.blocks:
      if b.kind == mbCodeBlock:
        codeBlock = b
        break
    check codeBlock.info == "python"
    check codeBlock.codeLines.len == 2
    check codeBlock.codeLines[0] == "def foo():"
    check codeBlock.codeLines[1] == "    return 42"

  test "atx_heading_levels_one_through_six":
    let source = "# h1\n## h2\n### h3\n#### h4\n##### h5\n###### h6\n"
    let doc = parseMarkdown(source)
    var hLevels: seq[int] = @[]
    for b in doc.blocks:
      if b.kind == mbHeading: hLevels.add b.level
    check hLevels == @[1, 2, 3, 4, 5, 6]

  test "setext_heading_underline":
    let source = "A heading\n=========\n\nAnother heading\n---------------\n"
    let doc = parseMarkdown(source)
    var hLevels: seq[int] = @[]
    for b in doc.blocks:
      if b.kind == mbHeading: hLevels.add b.level
    check hLevels == @[1, 2]

  test "thematic_break_dashes_and_stars":
    let source = "---\n***\n___\n"
    let doc = parseMarkdown(source)
    var count = 0
    for b in doc.blocks:
      if b.kind == mbHr: inc count
    check count == 3

  test "indented_code_block":
    let source = "Para\n\n    code line one\n    code line two\n"
    let doc = parseMarkdown(source)
    var foundCode = false
    for b in doc.blocks:
      if b.kind == mbCodeBlock:
        foundCode = true
        check b.codeLines == @["code line one", "code line two"]
    check foundCode

  test "inline_code_emphasis_link":
    let source = "Text with [a link](https://example.com) and `code` and " &
                 "*em* and **bold**.\n"
    let doc = parseMarkdown(source)
    check doc.blocks.len == 1
    check doc.blocks[0].kind == mbParagraph
    let inlines = doc.blocks[0].paragraph
    var sawLink = false
    var sawCode = false
    var sawEm = false
    var sawStrong = false
    for ix in inlines:
      case ix.kind
      of miLink:
        sawLink = true
        check ix.url == "https://example.com"
      of miCode:
        sawCode = true
        check ix.text == "code"
      of miEmphasis:
        sawEm = true
      of miStrong:
        sawStrong = true
      else: discard
    check sawLink
    check sawCode
    check sawEm
    check sawStrong

  test "slugify_basic_cases":
    check slugify("Hello World") == "hello-world"
    check slugify("Heading: With Punctuation!") == "heading-with-punctuation"
    check slugify("  leading and  trailing  ") == "leading-and-trailing"
    check slugify("snake_case_kept") == "snake_case_kept"

# ----------------------------------------------------------------------------
# The mandatory test: render Textual's README and verify structure.
# ----------------------------------------------------------------------------

suite "M20: Markdown widget renders Textual's README":

  test "test_markdown_renders_textual_readme":
    let candidates = @[
      "../isonim/refs/textual/README.md",
      "../../isonim/refs/textual/README.md",
      "isonim/refs/textual/README.md"]
    var readmePath = ""
    for c in candidates:
      if fileExists(c):
        readmePath = c
        break
    if readmePath.len == 0:
      skip()
    else:
      let source = readFile(readmePath)
      check source.len > 0

      # Real-stack mount: harness + compositor + renderer + Markdown widget.
      let h = newTerminalTestHarness(120, 60)
      var widget: MarkdownWidget
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        widget = newMarkdown(r, source = source, width = 100,
                             border = bsNone)
        r.appendChild(root, widget.node)
        root)

      # The widget must have parsed something.
      check widget.blockCount > 0

      # Heading structure: walk the parsed document, collect the
      # (level, anchor) tuples, and assert the curated golden matches.
      let actualHeadings = widget.headings()
      var actualTuples: seq[GoldenHeading] = @[]
      for h2 in actualHeadings:
        actualTuples.add (h2.level, h2.anchor)

      # The README's headings exactly match the golden.
      check actualTuples == TextualReadmeHeadings

      # The document carries enough paragraphs and code blocks that the
      # rendered output looks like real prose, not a stub.
      var paragraphs = 0
      var codeBlocks = 0
      proc walk(blocks: seq[MdBlock]) =
        for b in blocks:
          case b.kind
          of mbParagraph: inc paragraphs
          of mbCodeBlock: inc codeBlocks
          of mbQuote: walk(b.quoted)
          of mbList:
            for item in b.items: walk(item.blocks)
          else: discard
      walk(widget.document.blocks)
      check paragraphs >= MinParagraphs
      check codeBlocks >= MinCodeBlocks

      # The rendered tree must have produced rows. Each top-level child
      # of `widget.node` is one display row that the M8 compositor
      # flattens. We expect "many" rows for a 200-line README.
      check widget.node.children.len >= 30

      # Snapshot the structural fingerprint via the harness so a future
      # regression on the parser surfaces in the snapshot diff.
      discard h.snap("m20_markdown_textual_readme")

      h.dispose()

  test "markdown_viewer_with_toc":
    # MarkdownViewer composes Markdown + ToC sidebar + scrollable body.
    let source = """
# Chapter 1

Paragraph one.

## Section A

Another paragraph.

## Section B

Last paragraph.

# Chapter 2

End.
"""
    # Use a small viewport so the body overflows and scrolling is
    # actually meaningful (otherwise scrollTo clamps to 0 because the
    # body already fits in the viewport).
    let h = newTerminalTestHarness(80, 10)
    var viewer: MarkdownViewerWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      viewer = newMarkdownViewer(r, source = source,
                                 width = 80, height = 10,
                                 sidebarWidth = 20,
                                 border = bsNone)
      r.appendChild(root, viewer.node)
      root)

    check viewer.tocCount == 4
    check viewer.bodyRowCount > 0

    # ToC navigation: pressing Down from the start lands on entry 0.
    viewer.tocNext()
    check viewer.tocCursor == 0
    viewer.tocNext()
    check viewer.tocCursor == 1
    viewer.tocPrev()
    check viewer.tocCursor == 0

    # Scrolling — the body has ~13 rows but the viewport is only 10
    # (no border), so scrollTo(3) should hold (within range).
    viewer.scrollTo(3)
    check viewer.currentScroll == 3
    viewer.scrollTo(-100)
    check viewer.currentScroll == 0

    # Jump to a specific anchor.
    viewer.scrollToHeading("chapter-2")
    # The body should have scrolled (chapter-2 is the last heading,
    # so the row index for it is > 0).
    check viewer.currentScroll > 0

    h.dispose()
