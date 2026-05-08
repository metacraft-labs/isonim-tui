## widgets/footer.nim — Tier-3e `Footer` widget (M21).
##
## Port of `textual/widgets/_footer.py`. App chrome that docks at the
## bottom of the screen and renders a row of key bindings — every
## binding shows as `[KEY] description` separated by a thin gap. The
## footer is rebuilt whenever the binding list changes (typically when
## focus moves between widgets that publish different bindings).
##
## *Compact / verbose*: when `compact = true` the binding pairs render
## with no padding inside the key glyph; otherwise the key is wrapped
## with one space on each side. Mirrors `_footer.py`'s `compact`
## reactive.
##
## Charter §1: every public type is a value object; the widget itself
## is `ref` so the binding list can mutate after construction.

import ../renderer
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  FooterBinding* = object
    ## A single binding entry. `key` is the displayable shortcut
    ## (e.g. "q"), `description` is the user-facing label
    ## (e.g. "Quit"), and `disabled` greys the entry without removing
    ## it (mirrors Textual's `-disabled` class).
    key*: string
    description*: string
    disabled*: bool

  FooterWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    bindings*: seq[FooterBinding]
    width*: int
    compact*: bool
    keyFg*: string             ## Foreground colour for the key chip.
    keyBg*: string             ## Background colour for the key chip.
    descFg*: string            ## Foreground colour for descriptions.
    backgroundColor*: string   ## Footer-wide background.
    disabledFg*: string        ## Foreground colour for disabled chips.

# ----------------------------------------------------------------------------
# Forward decl
# ----------------------------------------------------------------------------
proc renderTree*(f: FooterWidget)

# ----------------------------------------------------------------------------
# Tree builder helpers
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; fg: string = ""; bg: string = "") =
  let box = r.createElement("div")
  if fg.len > 0: r.setStyle(box, "color", fg)
  if bg.len > 0: r.setStyle(box, "background-color", bg)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderEntry(b: FooterBinding; compact: bool): string =
  ## Build the visual chunk for a single binding. The colours are
  ## applied at the row level since the M8 compositor only accepts a
  ## single inline style per row in M11; per-segment colour-changes
  ## land alongside M5's full cascade.
  let key =
    if compact: "[" & b.key & "]"
    else: "[ " & b.key & " ]"
  if b.description.len == 0: key
  else: key & " " & b.description

# ----------------------------------------------------------------------------
# Renderer
# ----------------------------------------------------------------------------

proc renderTree*(f: FooterWidget) =
  let r = f.renderer
  clearTreeChildren(r, f.node)
  if f.bindings.len == 0:
    emitRow(r, f.node, spaces(f.width), f.descFg, f.backgroundColor)
    return
  var line = ""
  for i, b in f.bindings:
    if i > 0: line.add "  "
    line.add renderEntry(b, f.compact)
  let body = padOrTruncate(line, f.width)
  let fg =
    if f.bindings[0].disabled: f.disabledFg
    else: f.descFg
  emitRow(r, f.node, body, fg, f.backgroundColor)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newFooter*(renderer: TerminalRenderer;
                bindings: openArray[FooterBinding] = [];
                width: int = 80;
                compact: bool = true;
                keyFg: string = "white";
                keyBg: string = "blue";
                descFg: string = "white";
                backgroundColor: string = "";
                disabledFg: string = "bright_black"): FooterWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "footer")
  renderer.setAttribute(node, "class", "footer")
  var bs: seq[FooterBinding] = @[]
  for b in bindings: bs.add b
  let f = FooterWidget(
    renderer: renderer, node: node,
    bindings: bs,
    width: max(8, width),
    compact: compact,
    keyFg: keyFg, keyBg: keyBg, descFg: descFg,
    backgroundColor: backgroundColor,
    disabledFg: disabledFg)
  f.renderTree()
  f

# ----------------------------------------------------------------------------
# Public mutators
# ----------------------------------------------------------------------------

proc setBindings*(f: FooterWidget; bindings: openArray[FooterBinding]) =
  var bs: seq[FooterBinding] = @[]
  for b in bindings: bs.add b
  f.bindings = bs
  f.renderTree()

proc addBinding*(f: FooterWidget; binding: FooterBinding) =
  f.bindings.add binding
  f.renderTree()

proc clearBindings*(f: FooterWidget) =
  f.bindings.setLen(0)
  f.renderTree()

proc setCompact*(f: FooterWidget; compact: bool) =
  f.compact = compact
  f.renderTree()

proc id*(f: FooterWidget): int {.inline.} = f.node.id
