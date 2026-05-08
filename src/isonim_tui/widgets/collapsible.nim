## widgets/collapsible.nim — Tier-2 `Collapsible` widget (M14).
##
## Port of `textual/widgets/collapsible.py` (~718 LOC) — pragmatic
## core. A header row that toggles the visibility of a content panel
## beneath it. Expanding / collapsing is animated via the M7 animator:
## the inner row count interpolates from 0 → fullRows over
## `durationMs`, default 250 ms with `easeOutCubic`.
##
## API:
##
##   * `newCollapsible(harness, title, content, durationMs)`
##   * `collapsible.expand()` / `collapsible.collapse()` / `toggle()`
##   * `collapsible.expanded`  — bool
##   * `collapsible.visibleRows` — current animated row count (tests
##     use this to pin frames at t=0 / t=125 / t=250)
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ../events
import ../animation/easing
import ../animation/animator
import ../testing/harness

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  CollapsibleWidget* = ref object
    h*: TerminalTestHarness
    node*: TerminalNode               ## Outer container.
    header*: TerminalNode             ## Always-visible title bar.
    body*: TerminalNode               ## Animated content host.
    title*: string
    width*: int
    fullRows*: int                    ## Total content rows when fully open.
    contentRows*: seq[string]         ## Per-row strings, len == fullRows.
    expanded*: bool
    visibleRows*: int                 ## Current animated row count
                                      ## (0..fullRows).
    durationMs*: float64
    onToggle*: proc(expanded: bool)

# ----------------------------------------------------------------------------
# Forward decls
# ----------------------------------------------------------------------------
proc renderTree*(c: CollapsibleWidget)
proc expand*(c: CollapsibleWidget)
proc collapse*(c: CollapsibleWidget)
proc toggle*(c: CollapsibleWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let child = node.children[0]
    r.removeChild(node, child)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "";
             reverse: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderTree*(c: CollapsibleWidget) =
  let r = c.h.renderer
  # Header — always visible. Left-arrow when collapsed, down-arrow when
  # expanded (matches Textual's convention).
  clearTreeChildren(r, c.header)
  let arrow =
    if c.expanded: "\xE2\x96\xBC"  # ▼
    else: "\xE2\x96\xB6"          # ▶
  let hdr = arrow & " " & c.title
  emitRow(r, c.header, hdr, "", false)

  # Body — `visibleRows` worth of content. We rebuild on every paint so
  # animator-driven `visibleRows` mutations show up immediately.
  clearTreeChildren(r, c.body)
  let n = max(0, min(c.visibleRows, c.contentRows.len))
  for i in 0 ..< n:
    emitRow(r, c.body, c.contentRows[i])

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newCollapsible*(h: TerminalTestHarness;
                     title: string;
                     contentRows: openArray[string];
                     width: int = 30;
                     durationMs: float64 = 250.0;
                     initiallyExpanded: bool = false;
                     onToggle: proc(expanded: bool) = nil
                     ): CollapsibleWidget =
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "collapsible")
  r.setAttribute(node, "data-focusable", "true")
  r.setAttribute(node, "class", "collapsible")
  let header = r.createElement("div")
  r.setAttribute(header, "data-widget", "collapsible-header")
  let body = r.createElement("div")
  r.setAttribute(body, "data-widget", "collapsible-body")
  r.appendChild(node, header)
  r.appendChild(node, body)
  var rows: seq[string] = @[]
  for s in contentRows: rows.add s
  let c = CollapsibleWidget(
    h: h, node: node, header: header, body: body,
    title: title, width: max(1, width),
    fullRows: rows.len, contentRows: rows,
    expanded: initiallyExpanded,
    visibleRows: (if initiallyExpanded: rows.len else: 0),
    durationMs: durationMs, onToggle: onToggle)
  c.renderTree()

  # Activation: Space / Enter on the header toggles. The header is a
  # focusable zone with the toggling listener.
  r.setAttribute(header, "data-focusable", "true")
  r.addEventListener(header, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "space", "enter", "return":
      c.toggle()
    else: discard)
  r.addEventListener(header, "click", proc(ev: TerminalEvent) =
    c.toggle())
  # Forward keydown on the outer node to the same handler so harness-
  # level focus on `node` still toggles.
  r.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    if ev.kind != ekKey: return
    case ev.key.key
    of "space", "enter", "return":
      c.toggle()
    else: discard)
  c

# ----------------------------------------------------------------------------
# Toggle / animation
# ----------------------------------------------------------------------------

proc animateTo(c: CollapsibleWidget; targetRows: int;
               attribute: string) =
  let startRows = c.visibleRows.float64
  let endRows = targetRows.float64
  c.h.animator.animateFloat(
    targetId = c.node.id,
    attribute = attribute,
    startValue = startRows,
    endValue = endRows,
    durationMs = c.durationMs,
    easingFn = easeOutCubic,
    setter = proc(v: float64) =
      c.visibleRows = max(0, min(c.fullRows, int(v + 0.5)))
      c.renderTree()
      c.h.flush(),
    onComplete = proc() =
      c.visibleRows = targetRows
      c.renderTree()
      c.h.flush())

proc expand*(c: CollapsibleWidget) =
  if c.expanded: return
  c.expanded = true
  c.h.renderer.setAttribute(c.node, "data-expanded", "true")
  c.animateTo(c.fullRows, "collapsible-expand")
  if c.onToggle != nil: c.onToggle(true)

proc collapse*(c: CollapsibleWidget) =
  if not c.expanded: return
  c.expanded = false
  c.h.renderer.setAttribute(c.node, "data-expanded", "false")
  c.animateTo(0, "collapsible-collapse")
  if c.onToggle != nil: c.onToggle(false)

proc toggle*(c: CollapsibleWidget) =
  if c.expanded: c.collapse()
  else: c.expand()

proc setContent*(c: CollapsibleWidget; rows: openArray[string]) =
  var rs: seq[string] = @[]
  for r in rows: rs.add r
  c.contentRows = rs
  c.fullRows = rs.len
  if c.expanded:
    c.visibleRows = rs.len
  c.renderTree()

proc id*(c: CollapsibleWidget): int {.inline.} = c.node.id
