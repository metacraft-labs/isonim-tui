## isonim-tui terminal renderer.
##
## Production replacement for the demo renderer that used to live in
## `isonim/src/isonim/renderers/terminal.nim` (now `terminal_demo.nim`).
## Implements the full `RendererBackend` proc surface expected by
## `isonim/renderers/abstract_renderer.checkRendererBackend`, builds an
## in-memory tree of `TerminalNode`s, and exposes the same event-firing
## helpers as `mock_dom.nim` so existing component code is portable.
##
## The renderer maintains a per-thread monotonic node-id counter via a
## `{.threadvar.}` (mirrors `mock_dom.nim:40`). The counter resets to 0
## on each thread, so within a thread ids form a contiguous range
## starting at 1; across threads ids may collide but no test code crosses
## that boundary because each renderer instance carries its own thread
## affinity.
##
## *No real terminal output yet.* The compositor that turns this tree
## into a `ScreenBuffer` lands in M2 (test harness) and M8 (production
## compositor). M0's job is the type structure + the conformance proof.
##
## Charter footnote: the cell primitives in `cells.nim` are strict value
## types. The element-tree here uses `ref TerminalNode` for ergonomic
## parity with `MockNode`/`MockRenderer` so the same component code
## compiles against all three renderers — the constraint "no ref in the
## cell primitives" is what `cells.nim` honours; the element-tree shape
## is allowed to use ref objects per the milestone text.

import std/[tables]
import ./events

# ----------------------------------------------------------------------------
# Tree shape
# ----------------------------------------------------------------------------

type
  TerminalNodeKind* = enum
    tnkBox       ## Generic container (div, span, h1, …)
    tnkText      ## Text node
    tnkButton    ## Interactive button
    tnkInput     ## Text input

  TerminalNode* = ref object
    ## In-memory tree node. Mirrors `MockNode` and the demo renderer's
    ## `TerminalNode` so the existing renderer-agnostic test components
    ## compile unchanged.
    id*: int
    kind*: TerminalNodeKind
    tag*: string
    text*: string
    attributes*: Table[string, string]
    styles*: Table[string, string]
    children*: seq[TerminalNode]
    parent*: TerminalNode
    eventListeners*: Table[string, seq[proc()]]
    eventHandlers*: Table[string, seq[proc(ev: TerminalEvent)]]

  TerminalRenderer* = object
    ## Renderer backend. Empty value type: per-thread node-id state lives
    ## in the `nextTerminalNodeId` thread-var below. This means
    ## `checkRendererBackend[TerminalRenderer, TerminalNode]()`'s `var b: B`
    ## construction works as expected — every default-initialised renderer
    ## shares the same per-thread counter.

# Per-thread monotonic id counter. Mirrors `mock_dom.nim:40` exactly:
# without `{.threadvar.}` parallel test harnesses would race on a
# global. The bug fixed in the demo renderer (which used a plain
# `var nextTerminalNodeId*: int`) is *not present* here.
var nextTerminalNodeId* {.threadvar.}: int

proc resetNodeIds*() =
  ## Reset the thread-local counter. Tests that want deterministic ids
  ## across multiple harness instances on the same thread call this
  ## between mounts.
  nextTerminalNodeId = 0

proc nextNodeId*(): int {.inline.} =
  inc nextTerminalNodeId
  nextTerminalNodeId

# ----------------------------------------------------------------------------
# Tag → kind mapping
# ----------------------------------------------------------------------------

proc tagToKind*(tag: string): TerminalNodeKind =
  case tag
  of "button": tnkButton
  of "input": tnkInput
  else: tnkBox

# ----------------------------------------------------------------------------
# Required RendererBackend procs (the conformance surface)
# ----------------------------------------------------------------------------

proc createElement*(r: TerminalRenderer; tag: string): TerminalNode =
  TerminalNode(
    id: nextNodeId(),
    kind: tagToKind(tag),
    tag: tag,
    attributes: initTable[string, string](),
    styles: initTable[string, string](),
    children: @[],
    eventListeners: initTable[string, seq[proc()]](),
    eventHandlers: initTable[string, seq[proc(ev: TerminalEvent)]]()
  )

proc createTextNode*(r: TerminalRenderer; text: string): TerminalNode =
  TerminalNode(
    id: nextNodeId(),
    kind: tnkText,
    text: text,
    attributes: initTable[string, string](),
    styles: initTable[string, string](),
    eventListeners: initTable[string, seq[proc()]](),
    eventHandlers: initTable[string, seq[proc(ev: TerminalEvent)]]()
  )

proc appendChild*(r: TerminalRenderer; parent, child: TerminalNode) =
  child.parent = parent
  parent.children.add(child)

proc insertBefore*(r: TerminalRenderer; parent, child, reference: TerminalNode) =
  child.parent = parent
  var idx = -1
  for i, c in parent.children:
    if c == reference:
      idx = i
      break
  if idx >= 0:
    parent.children.insert(child, idx)
  else:
    parent.children.add(child)

proc removeChild*(r: TerminalRenderer; parent, child: TerminalNode) =
  child.parent = nil
  var idx = -1
  for i, c in parent.children:
    if c == child:
      idx = i
      break
  if idx >= 0:
    parent.children.delete(idx)

proc setAttribute*(r: TerminalRenderer; node: TerminalNode; name, value: string) =
  node.attributes[name] = value
  if name == "value":
    node.text = value

proc removeAttribute*(r: TerminalRenderer; node: TerminalNode; name: string) =
  node.attributes.del(name)

proc setTextContent*(r: TerminalRenderer; node: TerminalNode; text: string) =
  if node.kind == tnkText:
    node.text = text
  else:
    node.children.setLen(0)
    let textNode = TerminalNode(
      id: nextNodeId(),
      kind: tnkText,
      text: text,
      parent: node,
      attributes: initTable[string, string](),
      styles: initTable[string, string](),
      eventListeners: initTable[string, seq[proc()]](),
      eventHandlers: initTable[string, seq[proc(ev: TerminalEvent)]]()
    )
    node.children.add(textNode)

proc setStyle*(r: TerminalRenderer; node: TerminalNode; prop, value: string) =
  node.styles[prop] = value

proc addEventListener*(r: TerminalRenderer; node: TerminalNode; event: string;
                      handler: proc()) =
  ## No-arg handler overload. Mirrors the pattern in `mock_dom.nim:103`
  ## and `web_renderer.nim:84`: the DSL picks this overload when the
  ## user writes `onclick = () => doThing()`.
  if event notin node.eventListeners:
    node.eventListeners[event] = @[]
  node.eventListeners[event].add(handler)

proc addEventListener*(r: TerminalRenderer; node: TerminalNode; event: string;
                      handler: proc(ev: TerminalEvent)) =
  ## Event-arg handler overload. Mirrors `mock_dom.nim:124` and
  ## `web_renderer.nim:93`: the DSL picks this overload when the user
  ## writes `onclick = (ev) => ev.preventDefault()`.
  if event notin node.eventHandlers:
    node.eventHandlers[event] = @[]
  node.eventHandlers[event].add(handler)

proc firstChild*(r: TerminalRenderer; node: TerminalNode): TerminalNode =
  if node == nil or node.children.len == 0: nil
  else: node.children[0]

proc nextSibling*(r: TerminalRenderer; node: TerminalNode): TerminalNode =
  if node == nil or node.parent == nil: return nil
  let siblings = node.parent.children
  for i, c in siblings:
    if c == node and i + 1 < siblings.len:
      return siblings[i + 1]
  return nil

proc parentNode*(r: TerminalRenderer; node: TerminalNode): TerminalNode =
  if node == nil: nil else: node.parent

proc clearChildren*(r: TerminalRenderer; node: TerminalNode) =
  ## Remove all children from a node. Matches `MockRenderer.clearChildren`.
  for c in node.children:
    c.parent = nil
  node.children.setLen(0)

proc clearEventListeners*(r: TerminalRenderer; node: TerminalNode) =
  ## Remove all event listeners from a node. Matches
  ## `MockRenderer.clearEventListeners`.
  node.eventListeners.clear()
  node.eventHandlers.clear()

# ----------------------------------------------------------------------------
# Event firing helpers (for tests; production input lands in M2/M9/M10)
# ----------------------------------------------------------------------------

proc fireEvent*(node: TerminalNode; event: string) =
  ## Fire all handlers registered for the named event. The no-arg
  ## handlers run as-is; for event-arg handlers a synthetic
  ## `TerminalEvent` is constructed with `target` and `currentTarget`
  ## set to the node id.
  if event in node.eventListeners:
    for handler in node.eventListeners[event]:
      handler()
  if event in node.eventHandlers:
    let ev = newCustomEvent(event, node.id)
    for handler in node.eventHandlers[event]:
      handler(ev)

proc fireEventWith*(node: TerminalNode; event: string;
                   ev: TerminalEvent) =
  ## Variant that accepts a caller-supplied event so tests can inspect
  ## mutations like `defaultPrevented` after dispatch.
  if event in node.eventListeners:
    for handler in node.eventListeners[event]:
      handler()
  if event in node.eventHandlers:
    for handler in node.eventHandlers[event]:
      handler(ev)

proc textContent*(node: TerminalNode): string =
  ## Concatenated text content of the subtree rooted at `node`.
  if node.kind == tnkText:
    return node.text
  for child in node.children:
    result.add(textContent(child))

# ----------------------------------------------------------------------------
# Compile-time conformance
# ----------------------------------------------------------------------------
# The conformance proof. If any required RendererBackend proc is missing
# or has the wrong signature, this compile-time block fails with the
# `{.error.}` below — well before any test runs. M0's headline guarantee.

import isonim/renderers/abstract_renderer

when not compiles(checkRendererBackend[TerminalRenderer, TerminalNode]()):
  {.error: "isonim_tui.TerminalRenderer does not implement RendererBackend".}
