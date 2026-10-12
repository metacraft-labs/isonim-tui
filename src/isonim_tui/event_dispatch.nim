## isonim_tui/event_dispatch.nim — events that travel through the tree.
##
## Owns: `dispatchEvent`, the DOM's propagation over `TerminalNode`'s parent
## pointers — a capture phase from the root down to the target's parent, a
## target phase, and a bubble phase back up — honouring `stopPropagation`
## and reporting `preventDefault`, with `currentTargetId` and `phase` set
## for every listener that runs.
##
## Refuses to own: what any event MEANS. Which node is the target is the
## caller's answer (the focused node for a key, the hit node for a mouse
## report); this module only walks.
##
## `fireEvent` / `fireEventWith` (renderer.nim) stay what they were: the
## listeners of one node, nothing more. They are what a widget's own
## tests use, and changing them under those tests would change every
## widget's behaviour at once.
##
## THE ORDER, AS THE DOM DEFINES IT
##
##   1. capture: each ancestor, outermost first, its `capture` listeners;
##   2. target: the target's `capture` listeners, then its other
##      listeners, then the DSL's two handler tables (no-arg, then
##      event-arg — the latter on a copy, so it cannot stop the event);
##   3. bubble (only when `bubbles`): each ancestor, innermost first, its
##      non-capture listeners and then its DSL handlers.
##
## `stopPropagation` ends the walk after the current node's listeners have
## all run, as in the DOM (`stopImmediatePropagation` is not taken: nothing
## needs it). Only the event-arg listeners registered through
## `addEventListener(…, capture)` can stop it; the DSL's handlers see a
## copy.
##
## The path is computed ONCE, before the first listener runs: a listener
## that moves the target in the tree does not change where this event goes
## (the DOM's rule too).

import std/tables

import ./events
import ./renderer

proc propagationPath*(target: TerminalNode): seq[TerminalNode] =
  ## The target's ancestors and the target, OUTERMOST FIRST. A detached
  ## node's path is the node alone.
  result = @[]
  var n = target
  while n != nil:
    result.add n
    n = n.parent
  for i in 0 ..< result.len div 2:
    swap(result[i], result[result.len - 1 - i])

proc runListeners(node: TerminalNode; ev: var TerminalEvent;
                  capture: bool) =
  let registered = node.listeners.getOrDefault(ev.`type`)
  for listener in registered:
    if listener.capture == capture:
      listener.handler(ev)

proc runDslHandlers(node: TerminalNode; ev: var TerminalEvent) =
  for handler in node.eventListeners.getOrDefault(ev.`type`):
    handler()
  let copy = ev
  for handler in node.eventHandlers.getOrDefault(ev.`type`):
    handler(copy)

proc walk(path: seq[TerminalNode]; ev: var TerminalEvent; bubbles: bool) =
  ## The three phases over a computed path; returns early when a listener
  ## stopped the event.
  let target = path[^1]
  for i in 0 ..< path.len - 1:
    ev.phase = epCapturing
    ev.currentTargetId = path[i].id
    runListeners(path[i], ev, capture = true)
    if ev.propagationStopped:
      return
  ev.phase = epAtTarget
  ev.currentTargetId = target.id
  runListeners(target, ev, capture = true)
  runListeners(target, ev, capture = false)
  runDslHandlers(target, ev)
  if ev.propagationStopped or not bubbles:
    return
  for i in countdown(path.len - 2, 0):
    ev.phase = epBubbling
    ev.currentTargetId = path[i].id
    runListeners(path[i], ev, capture = false)
    runDslHandlers(path[i], ev)
    if ev.propagationStopped:
      return

proc dispatchEvent*(target: TerminalNode; ev: var TerminalEvent;
                    bubbles = true): bool =
  ## Dispatch `ev` (its `type` names the listeners) at `target`. Answers
  ## the DOM's `dispatchEvent` result: false when a listener called
  ## `preventDefault`. Afterwards `ev.phase` is `epNone` and
  ## `currentTargetId` 0, as the DOM leaves them; `propagationStopped` and
  ## `defaultPrevented` say what the listeners did.
  if target != nil:
    ev.targetId = target.id
    walk(propagationPath(target), ev, bubbles)
  ev.phase = epNone
  ev.currentTargetId = 0
  not ev.defaultPrevented
