## Introspection API — declarative queries against a mounted harness.
##
## Tree, computed-state, and render-state queries every later milestone
## tests against. Computed style is a placeholder until M5 (TCSS); for
## M2 it returns a default style record so tests can be written today.
##
## The queries operate on the harness's tree + last-rendered buffer.
## Nothing here mutates state; introspection is read-only.

import std/[strutils, tables]

import ../renderer
import ../compositor

# Forward types — we can't import harness here (circular); the harness
# passes its own state in. This keeps this module a *pure functions
# over data* layer.

type
  ComputedStyle* = object
    ## Placeholder for M5's full TCSS computed-style record. Returns a
    ## default-styled object today so tests can be written; M5 lands the
    ## real cascade.
    color*: string
    backgroundColor*: string
    display*: string
    visibility*: string

  LayoutRegion* = object
    row*: int
    col*: int
    width*: int
    height*: int

  EventLogEntry* = object
    seqNumber*: int
    targetId*: int
    eventType*: string

# ----------------------------------------------------------------------------
# Tree queries
# ----------------------------------------------------------------------------

proc findById*(root: TerminalNode; id: string): TerminalNode =
  ## DFS pre-order. Returns the first node whose `attributes["id"]`
  ## matches `id`, or `nil` if none.
  if root == nil: return nil
  if root.attributes.getOrDefault("id") == id:
    return root
  for child in root.children:
    let m = findById(child, id)
    if m != nil: return m
  return nil

proc walkByClass(n: TerminalNode; cls: string;
                 acc: var seq[TerminalNode]) =
  if n == nil: return
  let classes = n.attributes.getOrDefault("class")
  if classes.len > 0:
    for c in classes.split(' '):
      if c == cls:
        acc.add n
        break
  for child in n.children:
    walkByClass(child, cls, acc)

proc findByClass*(root: TerminalNode; cls: string): seq[TerminalNode] =
  ## All nodes whose space-separated `class` attribute contains `cls`.
  result = @[]
  if root == nil: return
  walkByClass(root, cls, result)

proc walkByTag(n: TerminalNode; tag: string;
               acc: var seq[TerminalNode]) =
  if n == nil: return
  if n.tag == tag: acc.add n
  for child in n.children:
    walkByTag(child, tag, acc)

proc findByTag*(root: TerminalNode; tag: string): seq[TerminalNode] =
  result = @[]
  if root == nil: return
  walkByTag(root, tag, result)

proc walkPredicate(n: TerminalNode;
                   predicate: proc(n: TerminalNode): bool;
                   acc: var seq[TerminalNode]) =
  if n == nil: return
  if predicate(n): acc.add n
  for child in n.children:
    walkPredicate(child, predicate, acc)

proc findAll*(root: TerminalNode;
              predicate: proc(n: TerminalNode): bool): seq[TerminalNode] =
  result = @[]
  if root == nil: return
  walkPredicate(root, predicate, result)

proc parent*(node: TerminalNode): TerminalNode {.inline.} =
  if node == nil: nil else: node.parent

proc children*(node: TerminalNode): seq[TerminalNode] =
  if node == nil: return @[]
  return node.children

proc walkDescendants(n: TerminalNode; acc: var seq[TerminalNode]) =
  for c in n.children:
    acc.add c
    walkDescendants(c, acc)

proc descendants*(node: TerminalNode): seq[TerminalNode] =
  result = @[]
  if node == nil: return
  walkDescendants(node, result)

proc ancestors*(node: TerminalNode): seq[TerminalNode] =
  result = @[]
  if node == nil: return
  var p = node.parent
  while p != nil:
    result.add p
    p = p.parent

# ----------------------------------------------------------------------------
# Computed state — placeholder until M5.
# ----------------------------------------------------------------------------

proc defaultComputedStyle*(): ComputedStyle =
  ComputedStyle(color: "default", backgroundColor: "default",
                display: "block", visibility: "visible")

proc computedStyleFor*(node: TerminalNode): ComputedStyle =
  ## Until M5 lands the real CSS engine the computed style is derived
  ## from inline `setStyle` calls (which already write to
  ## `node.styles`). Anything not set falls back to defaults.
  if node == nil: return defaultComputedStyle()
  result = defaultComputedStyle()
  if "color" in node.styles: result.color = node.styles["color"]
  if "background-color" in node.styles:
    result.backgroundColor = node.styles["background-color"]
  if "display" in node.styles: result.display = node.styles["display"]
  if "visibility" in node.styles:
    result.visibility = node.styles["visibility"]

proc layoutRegionForNode*(c: Compositor; root: TerminalNode;
                          node: TerminalNode): LayoutRegion =
  if node == nil:
    return LayoutRegion(row: 0, col: 0, width: 0, height: 0)
  let r = compositor.layoutRegionFor(c, root, node.id)
  LayoutRegion(row: r.row, col: r.col, width: r.width, height: r.height)

proc layoutRegionForId*(c: Compositor; root: TerminalNode;
                        nodeId: int): LayoutRegion =
  let r = compositor.layoutRegionFor(c, root, nodeId)
  LayoutRegion(row: r.row, col: r.col, width: r.width, height: r.height)

proc eventListenerCount*(node: TerminalNode; event: string): int =
  if node == nil: return 0
  var n = 0
  if event in node.eventListeners:
    n += node.eventListeners[event].len
  if event in node.eventHandlers:
    n += node.eventHandlers[event].len
  n

# ----------------------------------------------------------------------------
# dumpTree pretty-printer
# ----------------------------------------------------------------------------

proc dumpWalk(comp: Compositor; root, n: TerminalNode; depth: int;
              lines: var seq[string]) =
  let indent = "  ".repeat(depth)
  var idStr = ""
  if "id" in n.attributes: idStr = "#" & n.attributes["id"]
  var classStr = ""
  if "class" in n.attributes:
    for c in n.attributes["class"].split(' '):
      classStr.add "." & c
  let region = layoutRegionForNode(comp, root, n)
  let regionStr = " [" & $region.row & "," & $region.col & " " &
                  $region.width & "x" & $region.height & "]"
  let textStr =
    if n.kind == tnkText: " text=" & n.text.escape() else: ""
  lines.add indent & "<" & n.tag & idStr & classStr & ">" &
           regionStr & textStr
  for c in n.children:
    dumpWalk(comp, root, c, depth + 1, lines)

proc dumpTree*(c: Compositor; root: TerminalNode): string =
  ## Pretty-print the tree with id, classes, computed style, layout
  ## region. Exact format kept stable so tests can string-match.
  if root == nil: return "(nil)\n"
  var lines: seq[string] = @[]
  dumpWalk(c, root, root, 0, lines)
  result = lines.join("\n") & "\n"

# ----------------------------------------------------------------------------
# Event log
# ----------------------------------------------------------------------------
# (Type only — the harness owns the actual log.)

proc newEventLogEntry*(seqNumber, targetId: int; eventType: string): EventLogEntry =
  EventLogEntry(seqNumber: seqNumber, targetId: targetId, eventType: eventType)
