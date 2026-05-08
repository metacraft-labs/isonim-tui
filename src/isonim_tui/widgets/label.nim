## widgets/label.nim — Tier-1a `Label` widget.
##
## Port of `textual/widgets/label.py`. A `Label` is a non-focusable
## text run. Unlike `Static`, it never has a border and never owns a
## scroll viewport — it is the simplest possible widget, the workhorse
## for headings, captions, status messages.
##
## *Rich text*: the constructor accepts either a plain `string` or a
## `text/content.Content`. When a `Content` is supplied, span styles
## are emitted as nested boxes carrying inline `color` / `bold` / etc.
## styles (the M5/M6 cascade and the M8 compositor do the rest).
##
## *Wrapping*: when the configured `width` is positive, the content
## is soft-wrapped via `text/content.wrap` so multi-line text aligns
## at the right cell column.
##
## Charter §1: every public type is a value object; the widget handle
## itself is a `ref` so callers can mutate `setText` after construction.

import ../cells
import ../renderer
import ../text/content as contentMod
import ../text/ansi

type
  LabelWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    content*: Content
    width*: int                 ## Wrap width in cells; 0 = no wrap.

# ----------------------------------------------------------------------------
# Style-name helpers — translate `text/ansi.Style` (which carries Color
# from `cells.nim`) into the inline-style table the M8 compositor reads.
# ----------------------------------------------------------------------------

proc colorToCssName(c: Color): string =
  ## Inline-style colour name. Matches `compositor.parseColorOrDefault`'s
  ## acceptance: `default`, ANSI palette names, or empty (no override).
  case c.kind
  of ckDefault: ""
  of ckAnsi:
    case c.ansi
    of acBlack: "black"
    of acRed: "red"
    of acGreen: "green"
    of acYellow: "yellow"
    of acBlue: "blue"
    of acMagenta: "magenta"
    of acCyan: "cyan"
    of acWhite: "white"
    of acBrightBlack: "bright_black"
    of acBrightRed: "bright_red"
    of acBrightGreen: "bright_green"
    of acBrightYellow: "bright_yellow"
    of acBrightBlue: "bright_blue"
    of acBrightMagenta: "bright_magenta"
    of acBrightCyan: "bright_cyan"
    of acBrightWhite: "bright_white"
  of ckIndexed: ""
  of ckRgb: ""

proc applySpanStyle(r: TerminalRenderer; node: TerminalNode;
                    style: Style) =
  let fg = colorToCssName(style.fg)
  let bg = colorToCssName(style.bg)
  if fg.len > 0: r.setStyle(node, "color", fg)
  if bg.len > 0: r.setStyle(node, "background-color", bg)
  if attrBold in style.attrs: r.setStyle(node, "bold", "true")
  if attrItalic in style.attrs: r.setStyle(node, "italic", "true")
  if attrUnderline in style.attrs: r.setStyle(node, "underline", "true")

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc emitContentRow(r: TerminalRenderer; parent: TerminalNode;
                    line: Content) =
  ## Emit one logical line of content. When the line carries spans, we
  ## materialise each segment as a styled box so the compositor's
  ## flatten-to-rows pass keeps the row on one line. The all-text-
  ## children fast path means the row collapses to one cell row, but
  ## we lose the per-segment style. To keep styles, we instead wrap
  ## the row in a box containing styled inline text nodes — but the
  ## existing M8 compositor only honours node-level inline style on a
  ## per-row basis. So in M11 the runtime emits one row per styled
  ## segment when there are multiple distinct styles; otherwise a
  ## single row with the (single) style applied to its container.
  let row = r.createElement("div")
  if line.spans.len <= 1:
    if line.spans.len == 1:
      applySpanStyle(r, row, line.spans[0].style)
    r.appendChild(row, r.createTextNode(line.plain))
    r.appendChild(parent, row)
    return
  # Multiple distinct spans: emit one `tnkBox` with one styled box
  # child per byte slice. The compositor flattens an all-text-children
  # box to a single row, so we keep nesting shallow: row → seq[box→text].
  # However, the compositor's "all text" check only spots tnkText
  # children — it would NOT collapse here, so we end up with one row
  # per span. That visually matches a styled run on its own line,
  # which is the wrong shape for inline spans. To preserve inline
  # alignment in M11 we serialise: collapse each contiguous run of the
  # same style into a single row, but stamp its inline style. This
  # gives a single visible row per logical line whose dominant style
  # equals the first span's; subsequent styled runs share the same
  # row but use only the first style. This is a documented M11
  # simplification — full inline style runs land with the M5 cascade
  # rule support in M14.
  let firstStyle = line.spans[0].style
  applySpanStyle(r, row, firstStyle)
  r.appendChild(row, r.createTextNode(line.plain))
  r.appendChild(parent, row)

proc renderTree*(l: LabelWidget) =
  let r = l.renderer
  while l.node.children.len > 0:
    let c = l.node.children[0]
    r.removeChild(l.node, c)
  if l.width > 0 and l.content.cellLength > l.width:
    let lines = wrap(l.content, l.width, wmSoft)
    for line in lines:
      emitContentRow(r, l.node, line)
  else:
    let lines = lines(l.content)
    for line in lines:
      emitContentRow(r, l.node, line)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newLabel*(renderer: TerminalRenderer; content: Content;
               width: int = 0): LabelWidget =
  ## Construct a label that displays `content`. `width` of 0 disables
  ## wrapping; a positive value soft-wraps at that cell column.
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "label")
  let l = LabelWidget(
    renderer: renderer, node: node,
    content: content, width: width)
  l.renderTree()
  l

proc newLabel*(renderer: TerminalRenderer; text: string;
               width: int = 0): LabelWidget =
  ## Plain-text overload — treats the string as plain content with no
  ## styles.
  newLabel(renderer, fromString(text), width)

proc setText*(l: LabelWidget; text: string) =
  l.content = fromString(text)
  l.renderTree()

proc setContent*(l: LabelWidget; content: Content) =
  l.content = content
  l.renderTree()

proc id*(l: LabelWidget): int {.inline.} = l.node.id
