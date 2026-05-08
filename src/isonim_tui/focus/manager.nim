## isonim_tui/focus/manager.nim — focus order, navigation, traps.
##
## Port of the focus-handling concerns spread across Textual's
## `screen.py` (focus chain assembly) and `_compositor.py` (focus
## indication). The manager is the cross-cutting concern that every
## interactive widget in M12+ depends on: it owns the focus order
## derived from tree position, drives `Tab` / `Shift+Tab` navigation,
## supports a focus trap (used by M14's modal layer), and emits
## `focus` / `blur` events on the involved nodes.
##
## *Why a separate module?* Focus state lives on the harness today
## (`h.focusedId`), but the navigation logic (which is the same for
## every widget) belongs in one place. M12 widgets register themselves
## as focusable via the standard renderer attribute; the manager walks
## the tree and produces an ordered list of focusable node ids.
##
## Charter §1: every public type is a value object. The manager itself
## is a `ref object` because it owns mutable state (the focus stack,
## the trap stack); the focus chain it returns is a value `seq[int]`.

import std/[strutils, tables]

import ../renderer
import ../events

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  FocusManager* = ref object
    ## Cross-cutting focus state. Holds the current focused node id
    ## (mirrors `harness.focusedId` so both can be queried), and the
    ## stack of trap roots installed by modal layers.
    focusedId*: int                  ## 0 = no focus.
    trapStack*: seq[int]             ## Top of stack = current trap root id;
                                     ## empty = no trap (whole tree).

  FocusChange* = object
    ## Result of a navigation step. `oldId` and `newId` may be 0.
    ## `wrapped` is true when the navigation rolled past the end (Tab
    ## from the last focusable lands on the first; Shift+Tab the
    ## reverse).
    oldId*: int
    newId*: int
    wrapped*: bool

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newFocusManager*(): FocusManager =
  FocusManager(focusedId: 0, trapStack: @[])

# ----------------------------------------------------------------------------
# Focusable predicate
# ----------------------------------------------------------------------------

proc isFocusable*(node: TerminalNode): bool =
  ## A node participates in the focus chain when it carries the
  ## `data-focusable="true"` attribute (set by every interactive
  ## widget's constructor) AND is not marked disabled.
  if node == nil: return false
  if node.attributes.getOrDefault("disabled") != "": return false
  node.attributes.getOrDefault("data-focusable") == "true"

# ----------------------------------------------------------------------------
# Focus chain assembly — DFS pre-order under the active trap.
# ----------------------------------------------------------------------------

proc trapRootOf(fm: FocusManager; root: TerminalNode): TerminalNode =
  ## Resolve the active trap root: top of the stack if non-empty,
  ## otherwise the supplied tree root. Walks the tree to find the
  ## node by id.
  if fm.trapStack.len == 0 or root == nil: return root
  let trapId = fm.trapStack[^1]
  proc walk(n: TerminalNode): TerminalNode =
    if n == nil: return nil
    if n.id == trapId: return n
    for c in n.children:
      let m = walk(c)
      if m != nil: return m
    return nil
  let r = walk(root)
  if r == nil: root else: r

proc collectFocusable(n: TerminalNode; acc: var seq[int]) =
  if n == nil: return
  if isFocusable(n):
    acc.add n.id
  for c in n.children:
    collectFocusable(c, acc)

proc focusChain*(fm: FocusManager; root: TerminalNode): seq[int] =
  ## DFS pre-order list of focusable node ids under the active trap.
  ## The order matches tree position so nested widgets get a sensible
  ## tab cycle out of the box.
  result = @[]
  let trap = trapRootOf(fm, root)
  if trap == nil: return
  collectFocusable(trap, result)

# ----------------------------------------------------------------------------
# Helpers — find by id, fire focus/blur listeners.
# ----------------------------------------------------------------------------

proc nodeById(root: TerminalNode; id: int): TerminalNode =
  if root == nil or id == 0: return nil
  if root.id == id: return root
  for c in root.children:
    let m = nodeById(c, id)
    if m != nil: return m
  return nil

proc fireFocusEvent(node: TerminalNode; name: string) =
  ## Dispatch a synthetic `focus` / `blur` event on the target. The
  ## DSL picks up listeners via the standard `addEventListener` calls
  ## (no-arg or event-arg overload).
  if node == nil: return
  var ev = TerminalEvent(
    kind: (if name == "focus": ekFocus else: ekBlur),
    `type`: name, targetId: node.id, currentTargetId: node.id)
  fireEventWith(node, name, ev)

# ----------------------------------------------------------------------------
# Setting focus
# ----------------------------------------------------------------------------

proc setFocus*(fm: FocusManager; root: TerminalNode; nodeId: int): FocusChange =
  ## Move focus to the node with id `nodeId` (or 0 to clear). Fires
  ## `blur` on the previously-focused node and `focus` on the new
  ## one. No-ops when the target is already focused.
  result = FocusChange(oldId: fm.focusedId, newId: nodeId, wrapped: false)
  if fm.focusedId == nodeId: return
  let oldNode = nodeById(root, fm.focusedId)
  fireFocusEvent(oldNode, "blur")
  fm.focusedId = nodeId
  let newNode = nodeById(root, nodeId)
  fireFocusEvent(newNode, "focus")

proc clearFocus*(fm: FocusManager; root: TerminalNode) =
  discard fm.setFocus(root, 0)

proc setFocusByNode*(fm: FocusManager; root: TerminalNode;
                    target: TerminalNode): FocusChange =
  let id = if target == nil: 0 else: target.id
  fm.setFocus(root, id)

# ----------------------------------------------------------------------------
# Tab / Shift+Tab navigation
# ----------------------------------------------------------------------------

proc focusNext*(fm: FocusManager; root: TerminalNode): FocusChange =
  ## Advance focus to the next focusable node in tree order. Wraps
  ## from last → first. Returns `FocusChange{0,0,false}` when the
  ## chain is empty.
  let chain = fm.focusChain(root)
  if chain.len == 0:
    return FocusChange(oldId: fm.focusedId, newId: 0, wrapped: false)
  let cur = fm.focusedId
  var idx = -1
  for i, id in chain:
    if id == cur:
      idx = i
      break
  let nextIdx = (idx + 1) mod chain.len
  let wrapped = idx == chain.len - 1 or idx < 0
  let nextId = chain[nextIdx]
  result = fm.setFocus(root, nextId)
  result.wrapped = wrapped

proc focusPrev*(fm: FocusManager; root: TerminalNode): FocusChange =
  ## Reverse of `focusNext`. Wraps from first → last.
  let chain = fm.focusChain(root)
  if chain.len == 0:
    return FocusChange(oldId: fm.focusedId, newId: 0, wrapped: false)
  let cur = fm.focusedId
  var idx = -1
  for i, id in chain:
    if id == cur:
      idx = i
      break
  var prevIdx: int
  var wrapped = false
  if idx <= 0:
    prevIdx = chain.len - 1
    wrapped = true
  else:
    prevIdx = idx - 1
  let prevId = chain[prevIdx]
  result = fm.setFocus(root, prevId)
  result.wrapped = wrapped

# ----------------------------------------------------------------------------
# Focus trap (modals, M14)
# ----------------------------------------------------------------------------

proc pushTrap*(fm: FocusManager; rootId: int) =
  ## Constrain navigation to the subtree rooted at `rootId`. Only
  ## focusable descendants of that node participate in the chain.
  ## Modal widgets (M14) call this on open; they pop on close.
  fm.trapStack.add rootId

proc popTrap*(fm: FocusManager) =
  if fm.trapStack.len > 0:
    fm.trapStack.setLen(fm.trapStack.len - 1)

proc currentTrap*(fm: FocusManager): int =
  if fm.trapStack.len == 0: 0
  else: fm.trapStack[^1]

# ----------------------------------------------------------------------------
# Convenience: handle a Tab/Shift-Tab event
# ----------------------------------------------------------------------------

proc handleKey*(fm: FocusManager; root: TerminalNode;
                ev: TerminalEvent): bool =
  ## Returns true when the event was a Tab / Shift+Tab and was
  ## consumed by the focus manager. Callers route the bubble phase
  ## through this so an unhandled key falls back to the focused
  ## widget's own listeners.
  if ev.kind != ekKey: return false
  let name = ev.key.key.toLowerAscii
  if name == "tab" and modShift in ev.key.modifiers:
    discard fm.focusPrev(root)
    return true
  if name == "shift+tab":
    discard fm.focusPrev(root)
    return true
  if name == "tab":
    discard fm.focusNext(root)
    return true
  return false
