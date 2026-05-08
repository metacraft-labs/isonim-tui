## widgets/markdown_viewer.nim — Tier-3d `MarkdownViewer` widget (M20).
##
## Port of the `MarkdownViewer` half of `textual/widgets/markdown.py`.
## Composes a `MarkdownWidget` body with a scrollable shell and a
## table-of-contents sidebar built from the document's headings.
##
## Layout (when `showTableOfContents` is on):
##
## ```
## ┌────────────────┬─────────────────────────────┐
## │ Table of       │ # Heading 1                 │
## │ Contents       │                             │
## │   Heading 1    │ Body paragraph...           │
## │   Heading 2    │                             │
## │     Sub        │ ## Heading 2                │
## │ ...            │ ...                         │
## └────────────────┴─────────────────────────────┘
## ```
##
## Scrolling: `PgUp` / `PgDn` move by `viewportHeight - 1` rows;
## `Up` / `Down` move by one row; `Home` / `End` jump to the document
## top / bottom; `Tab` cycles through the ToC entries (the sidebar
## acts like a focusable list, so pressing `Enter` scrolls the body
## to the corresponding heading).

import std/[strutils, tables]

import ../renderer
import ../events
import ../css/properties
import ../text/width as widthMod
import ./borders
import ./markdown

type
  TocEntry* = object
    level*: int
    text*: string
    anchor*: string
    bodyRow*: int            ## Row index in the body where this heading
                             ## starts. Filled in after the body is
                             ## flattened so `Enter` can jump directly.

  MarkdownViewerWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    body*: MarkdownWidget
    width*: int
    height*: int
    sidebarWidth*: int
    showTableOfContents*: bool
    border*: BorderStyle
    borderColor*: string
    scrollY*: int
    tocEntries*: seq[TocEntry]
    tocCursor*: int                ## -1 = no selection
    bodyRows*: seq[seq[InlineSpan]] ## Cached flattened body rows.

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------

proc renderTree*(v: MarkdownViewerWidget)
proc setMarkdown*(v: MarkdownViewerWidget; source: string)
proc scrollTo*(v: MarkdownViewerWidget; row: int)
proc scrollToHeading*(v: MarkdownViewerWidget; anchor: string)
proc selectTocEntry*(v: MarkdownViewerWidget; index: int)
proc pageUp*(v: MarkdownViewerWidget)
proc pageDown*(v: MarkdownViewerWidget)

# ----------------------------------------------------------------------------
# Body flattening — convert the markdown widget's nested DOM into a flat
# list of inline-span rows, plus a row→heading map for ToC navigation.
# ----------------------------------------------------------------------------

proc walkSpan(n: TerminalNode; bold, italic, underline: bool;
              color: string; acc: var seq[InlineSpan]) =
  if n.kind == tnkText:
    acc.add InlineSpan(text: n.text, color: color, bold: bold,
                       italic: italic, underline: underline)
    return
  var c = color
  if n.styles.hasKey("color"): c = n.styles["color"]
  var b = bold
  if n.styles.hasKey("bold") and n.styles["bold"] == "true": b = true
  var i = italic
  if n.styles.hasKey("italic") and n.styles["italic"] == "true": i = true
  var u = underline
  if n.styles.hasKey("underline") and n.styles["underline"] == "true":
    u = true
  for child in n.children:
    walkSpan(child, b, i, u, c, acc)

proc inlineSpansFromNode(node: TerminalNode): seq[InlineSpan] =
  ## Walk one rendered row's children, materialising each text segment
  ## into a `InlineSpan`. Mirrors the inverse of `emitSpannedRow` in
  ## `markdown.nim`.
  result = @[]
  walkSpan(node, false, false, false, "", result)

proc flattenBody(v: MarkdownViewerWidget) =
  ## Re-render the body widget's current document, then snapshot its
  ## row tree into `v.bodyRows` and record per-heading body row offsets.
  v.bodyRows = @[]
  for child in v.body.node.children:
    v.bodyRows.add inlineSpansFromNode(child)
  # Map heading anchors to body rows by matching the heading's plain
  # text against the first non-blank inline span on each row. This
  # is an approximation but holds for the rendering produced by
  # `markdown.renderBlocks`: every heading lands on a row that begins
  # with `# ` / `## ` / etc.
  let headings = v.body.headings()
  v.tocEntries = @[]
  var hIdx = 0
  for rowIdx, row in v.bodyRows:
    if hIdx >= headings.len: break
    let prefix =
      case headings[hIdx].level
      of 1: "#"
      of 2: "##"
      of 3: "###"
      of 4: "####"
      of 5: "#####"
      of 6: "######"
      else: "#"
    # Concatenate the leading non-blank spans to find the heading prefix.
    # The wrap logic splits `# heading-text` into separate spans for the
    # `#`, the space, and each word, so we look at the *first* non-empty
    # span and check it equals the expected hash run exactly. The heading
    # is detected when the leading span is `#`/`##`/etc. and the following
    # span is a single space or whitespace.
    var leadIdx = 0
    while leadIdx < row.len and row[leadIdx].text.len == 0:
      inc leadIdx
    if leadIdx < row.len and row[leadIdx].text == prefix and
       row[leadIdx].bold:
      v.tocEntries.add TocEntry(
        level: headings[hIdx].level,
        text: headings[hIdx].text,
        anchor: headings[hIdx].anchor,
        bodyRow: rowIdx)
      inc hIdx

# ----------------------------------------------------------------------------
# Tree builders
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitTextRow(r: TerminalRenderer; parent: TerminalNode;
                 text: string; color = ""; bold = false;
                 italic = false; underline = false; reverse = false) =
  let row = r.createElement("div")
  if color.len > 0: r.setStyle(row, "color", color)
  if bold: r.setStyle(row, "bold", "true")
  if italic: r.setStyle(row, "italic", "true")
  if underline: r.setStyle(row, "underline", "true")
  if reverse: r.setStyle(row, "reverse", "true")
  r.appendChild(row, r.createTextNode(text))
  r.appendChild(parent, row)

proc emitSpansRow(r: TerminalRenderer; parent: TerminalNode;
                  prefix: string; spans: seq[InlineSpan];
                  width: int) =
  let row = r.createElement("div")
  var totalW = 0
  if prefix.len > 0:
    let pBox = r.createElement("span")
    r.appendChild(pBox, r.createTextNode(prefix))
    r.appendChild(row, pBox)
    totalW += widthMod.displayWidth(prefix)
  for s in spans:
    if s.text.len == 0: continue
    let segBox = r.createElement("span")
    if s.color.len > 0: r.setStyle(segBox, "color", s.color)
    if s.bold: r.setStyle(segBox, "bold", "true")
    if s.italic: r.setStyle(segBox, "italic", "true")
    if s.underline: r.setStyle(segBox, "underline", "true")
    r.appendChild(segBox, r.createTextNode(s.text))
    r.appendChild(row, segBox)
    totalW += widthMod.displayWidth(s.text)
  if totalW < width:
    let pad = r.createElement("span")
    r.appendChild(pad, r.createTextNode(spaces(width - totalW)))
    r.appendChild(row, pad)
  r.appendChild(parent, row)

proc renderSidebar(v: MarkdownViewerWidget; parent: TerminalNode;
                   innerWidth, innerHeight: int) =
  let r = v.renderer
  emitTextRow(r, parent, padOrTruncate("Table of Contents", innerWidth),
              bold = true)
  let separator = block:
    var s = ""
    var w = 0
    while w < innerWidth:
      s.add "─"
      w += 1
    s
  emitTextRow(r, parent, separator)
  let visibleEntries = max(0, innerHeight - 2)
  for i in 0 ..< visibleEntries:
    if i < v.tocEntries.len:
      let entry = v.tocEntries[i]
      let indent = spaces(max(0, (entry.level - 1) * 2))
      let line = padOrTruncate(indent & entry.text, innerWidth)
      let isSelected = i == v.tocCursor
      emitTextRow(r, parent, line, reverse = isSelected)
    else:
      emitTextRow(r, parent, spaces(innerWidth))

proc renderBody(v: MarkdownViewerWidget; parent: TerminalNode;
                innerWidth, innerHeight: int) =
  let r = v.renderer
  let totalRows = v.bodyRows.len
  let maxScroll = max(0, totalRows - innerHeight)
  if v.scrollY > maxScroll: v.scrollY = maxScroll
  if v.scrollY < 0: v.scrollY = 0
  for i in 0 ..< innerHeight:
    let rowIdx = v.scrollY + i
    if rowIdx < totalRows:
      emitSpansRow(r, parent, "", v.bodyRows[rowIdx], innerWidth)
    else:
      emitTextRow(r, parent, spaces(innerWidth))

proc renderTree*(v: MarkdownViewerWidget) =
  let r = v.renderer
  flattenBody(v)
  clearTreeChildren(r, v.node)
  let glyphs = bordersGlyphs(v.border)
  let useBorder = v.border != bsNone
  let outerInner = max(1, v.width - (if useBorder: 2 else: 0))
  let outerHeight = max(1, v.height - (if useBorder: 2 else: 0))
  if useBorder:
    emitTextRow(r, v.node, topBorderRow(glyphs, outerInner), v.borderColor)
  let sidebarW = if v.showTableOfContents: max(1, v.sidebarWidth) else: 0
  let bodyW =
    if v.showTableOfContents: max(1, outerInner - sidebarW - 1)
    else: outerInner
  # Build per-row composite: sidebar + separator + body, both clipped
  # to `outerHeight`.
  let sidebarHost = r.createElement("div")
  let bodyHost = r.createElement("div")
  if v.showTableOfContents:
    renderSidebar(v, sidebarHost, sidebarW, outerHeight)
  renderBody(v, bodyHost, bodyW, outerHeight)
  let sidebarRows = sidebarHost.children
  let bodyRows = bodyHost.children
  for i in 0 ..< outerHeight:
    let row = r.createElement("div")
    if useBorder:
      let leftBox = r.createElement("span")
      if v.borderColor.len > 0: r.setStyle(leftBox, "color", v.borderColor)
      r.appendChild(leftBox, r.createTextNode(glyphs.left))
      r.appendChild(row, leftBox)
    if v.showTableOfContents and i < sidebarRows.len:
      let sb = sidebarRows[i]
      while sb.children.len > 0:
        let cc = sb.children[0]
        r.removeChild(sb, cc)
        r.appendChild(row, cc)
      # Separator
      let sep = r.createElement("span")
      r.appendChild(sep, r.createTextNode("│"))
      r.appendChild(row, sep)
    if i < bodyRows.len:
      let br = bodyRows[i]
      while br.children.len > 0:
        let cc = br.children[0]
        r.removeChild(br, cc)
        r.appendChild(row, cc)
    if useBorder:
      let rightBox = r.createElement("span")
      if v.borderColor.len > 0: r.setStyle(rightBox, "color", v.borderColor)
      r.appendChild(rightBox, r.createTextNode(glyphs.right))
      r.appendChild(row, rightBox)
    r.appendChild(v.node, row)
  if useBorder:
    emitTextRow(r, v.node, bottomBorderRow(glyphs, outerInner), v.borderColor)

# ----------------------------------------------------------------------------
# Mutation + scrolling
# ----------------------------------------------------------------------------

proc setMarkdown*(v: MarkdownViewerWidget; source: string) =
  v.body.setMarkdown(source)
  v.scrollY = 0
  v.tocCursor = -1
  v.renderTree()

proc scrollTo*(v: MarkdownViewerWidget; row: int) =
  let useBorder = v.border != bsNone
  let outerHeight = max(1, v.height - (if useBorder: 2 else: 0))
  let totalRows = v.bodyRows.len
  let maxScroll = max(0, totalRows - outerHeight)
  v.scrollY = max(0, min(row, maxScroll))
  v.renderTree()

proc scrollToHeading*(v: MarkdownViewerWidget; anchor: string) =
  for entry in v.tocEntries:
    if entry.anchor == anchor:
      v.scrollTo(entry.bodyRow)
      return

proc selectTocEntry*(v: MarkdownViewerWidget; index: int) =
  if index < 0 or index >= v.tocEntries.len: return
  v.tocCursor = index
  v.scrollTo(v.tocEntries[index].bodyRow)

proc tocNext*(v: MarkdownViewerWidget) =
  if v.tocEntries.len == 0: return
  let next = if v.tocCursor < 0: 0
             else: min(v.tocCursor + 1, v.tocEntries.len - 1)
  v.selectTocEntry(next)

proc tocPrev*(v: MarkdownViewerWidget) =
  if v.tocEntries.len == 0: return
  let prev = if v.tocCursor <= 0: 0 else: v.tocCursor - 1
  v.selectTocEntry(prev)

proc pageUp*(v: MarkdownViewerWidget) =
  let useBorder = v.border != bsNone
  let outerHeight = max(1, v.height - (if useBorder: 2 else: 0))
  let step = max(1, outerHeight - 1)
  v.scrollTo(v.scrollY - step)

proc pageDown*(v: MarkdownViewerWidget) =
  let useBorder = v.border != bsNone
  let outerHeight = max(1, v.height - (if useBorder: 2 else: 0))
  let step = max(1, outerHeight - 1)
  v.scrollTo(v.scrollY + step)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newMarkdownViewer*(renderer: TerminalRenderer;
                        source: string = "";
                        width: int = 80;
                        height: int = 24;
                        sidebarWidth: int = 24;
                        showTableOfContents: bool = true;
                        border: BorderStyle = bsRound;
                        borderColor: string = "";
                        bodyColor: string = ""): MarkdownViewerWidget =
  let actualWidth = max(10, width)
  let actualHeight = max(3, height)
  let actualSidebar = if showTableOfContents: max(1, sidebarWidth) else: 0
  let useBorder = border != bsNone
  let outerInner = actualWidth - (if useBorder: 2 else: 0)
  let bodyWidth =
    if showTableOfContents: max(1, outerInner - actualSidebar - 1)
    else: outerInner
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "markdown-viewer")
  renderer.setAttribute(node, "class", "markdown-viewer")
  renderer.setAttribute(node, "data-focusable", "true")
  let body = newMarkdown(renderer, source = source, width = bodyWidth,
                         border = bsNone, color = bodyColor)
  let v = MarkdownViewerWidget(
    renderer: renderer,
    node: node,
    body: body,
    width: actualWidth,
    height: actualHeight,
    sidebarWidth: actualSidebar,
    showTableOfContents: showTableOfContents,
    border: border,
    borderColor: borderColor,
    scrollY: 0,
    tocEntries: @[],
    tocCursor: -1,
    bodyRows: @[])
  v.renderTree()
  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key.toLowerAscii
    of "pagedown", "pagedn":
      v.pageDown()
    of "pageup":
      v.pageUp()
    of "down":
      if v.showTableOfContents:
        v.tocNext()
      else:
        v.scrollTo(v.scrollY + 1)
    of "up":
      if v.showTableOfContents:
        v.tocPrev()
      else:
        v.scrollTo(v.scrollY - 1)
    of "home":
      v.scrollTo(0)
    of "end":
      v.scrollTo(v.bodyRows.len)
    of "enter", "return":
      if v.tocCursor >= 0 and v.tocCursor < v.tocEntries.len:
        v.scrollTo(v.tocEntries[v.tocCursor].bodyRow)
    else: discard)
  v

# ----------------------------------------------------------------------------
# Convenience accessors used by tests.
# ----------------------------------------------------------------------------

proc id*(v: MarkdownViewerWidget): int {.inline.} = v.node.id

proc tocCount*(v: MarkdownViewerWidget): int {.inline.} =
  v.tocEntries.len

proc bodyRowCount*(v: MarkdownViewerWidget): int {.inline.} =
  v.bodyRows.len

proc currentScroll*(v: MarkdownViewerWidget): int {.inline.} = v.scrollY
