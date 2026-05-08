## widgets/content_switcher.nim — Tier-2 `ContentSwitcher` widget (M14).
##
## Port of `textual/widgets/_content_switcher.py`. A container that
## owns N child panes (each tagged with a stable `id` string) and
## shows exactly one of them at a time. Switching is by id; the
## widget walks its registered panes, hiding all others and exposing
## the active one as the only visible child of the underlying node.
##
## This is the core primitive `TabbedContent` composes: Tabs +
## ContentSwitcher = tabbed pages. ContentSwitcher itself doesn't
## render any chrome — it's a pure router.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  ContentPane* = object
    ## One pane in the switcher. `id` is the stable lookup key;
    ## `node` is the pane's root TerminalNode.
    id*: string
    node*: TerminalNode

  ContentSwitcherWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    panes*: seq[ContentPane]
    activeId*: string
    onChange*: proc(oldId, newId: string)

# ----------------------------------------------------------------------------
# Tree management
# ----------------------------------------------------------------------------

proc renderTree*(s: ContentSwitcherWidget) =
  ## Sync the underlying node's children with the active pane: only
  ## the matching pane node is mounted; others are removed from the
  ## tree (their handles still live in `s.panes` so they can be
  ## remounted on the next switch).
  let r = s.renderer
  while s.node.children.len > 0:
    let c = s.node.children[0]
    r.removeChild(s.node, c)
  for pane in s.panes:
    if pane.id == s.activeId:
      r.appendChild(s.node, pane.node)
      return

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newContentSwitcher*(renderer: TerminalRenderer;
                         initialId: string = "";
                         onChange: proc(oldId,
                                        newId: string) = nil
                         ): ContentSwitcherWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "content-switcher")
  renderer.setAttribute(node, "class", "content-switcher")
  ContentSwitcherWidget(
    renderer: renderer, node: node,
    panes: @[], activeId: initialId,
    onChange: onChange)

proc addPane*(s: ContentSwitcherWidget; id: string;
              pane: TerminalNode) =
  ## Register a pane. If no active id has been set yet, the first
  ## registered pane becomes active. Subsequent registrations leave
  ## the active id alone (apps that need to swap should call
  ## `switchTo`).
  s.panes.add ContentPane(id: id, node: pane)
  s.renderer.setAttribute(pane, "data-pane-id", id)
  if s.activeId.len == 0:
    s.activeId = id
  s.renderTree()

proc switchTo*(s: ContentSwitcherWidget; id: string) =
  ## Activate the pane with the given id. No-op when the id doesn't
  ## match any registered pane or matches the current active id.
  if id == s.activeId: return
  var found = false
  for pane in s.panes:
    if pane.id == id:
      found = true
      break
  if not found: return
  let oldId = s.activeId
  s.activeId = id
  s.renderTree()
  if s.onChange != nil:
    s.onChange(oldId, id)

proc paneIds*(s: ContentSwitcherWidget): seq[string] =
  result = @[]
  for pane in s.panes:
    result.add pane.id

proc id*(s: ContentSwitcherWidget): int {.inline.} = s.node.id
