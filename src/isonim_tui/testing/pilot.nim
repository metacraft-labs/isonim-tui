## Pilot — programmable input. Nim port of `textual/pilot.py`.
##
## A `Pilot` is attached to a harness via `newPilot(h)`. Each method
## injects synthetic events into the driver, fires the matching DOM-
## style listeners on the targeted node, and triggers a flush so the
## resulting paint commits before control returns.
##
## Parity with Textual:
##   press, type, click, doubleClick, tripleClick, hover, mouseDown,
##   mouseUp, scroll, focus, paste, resize, waitFor, pause,
##   waitForAnimation, waitForScheduledAnimations, exit.

import std/[unicode, strutils]

import ../events
import ../renderer
import ../drivers/headless_driver
import ./harness

# Convert isonim/core/clock TestClock if needed — already pulled in by
# harness through transitive imports.

type
  Pilot* = ref object
    ## Input-driver attached to a harness. Borrows the harness pointer
    ## (no ownership). Stores no state of its own beyond a back-ref —
    ## actions read/write through the harness.
    h*: TerminalTestHarness

  PilotResult* = object
    ## The result of `exit(value)`. Tests use this to signal a "done"
    ## condition from a pilot script that may run multiple actions.
    exited*: bool
    value*: int

proc newPilot*(h: TerminalTestHarness): Pilot =
  Pilot(h: h)

# ----------------------------------------------------------------------------
# Event firing helpers
# ----------------------------------------------------------------------------

proc fireKeyEvent(p: Pilot; targetId: int; eventName, keyName: string;
                  rune: uint32; modifiers: set[Modifier];
                  kind: KeyKind) =
  ## Inject a key event into the driver, fire DOM-style listeners on
  ## the target, record the event in the harness log.
  let key = newKeyEvent(keyName, rune, modifiers, kind)
  let ev = newKeyTerminalEvent(eventName, key, targetId)
  p.h.driver.injectEvent(ev)
  # Drain so pilot semantics match: the event was both queued and
  # delivered.
  discard p.h.driver.readEvents()
  if targetId != 0 and p.h.root != nil:
    proc walk(n: TerminalNode) =
      if n == nil: return
      if n.id == targetId:
        fireEventWith(n, eventName, ev)
        return
      # Snapshot children before iterating: event listeners may mutate
      # the tree (mount modals, swap content panes, etc.) and we don't
      # want the iterator to fault when the seq grows mid-walk.
      var snapshot = newSeq[TerminalNode](n.children.len)
      for i in 0 ..< n.children.len: snapshot[i] = n.children[i]
      for c in snapshot: walk(c)
    walk(p.h.root)
  p.h.recordEvent(targetId, eventName)
  p.h.flush()

proc fireMouseEvent(p: Pilot; eventName: string; mouse: MouseEvent;
                    targetId: int = 0) =
  var ev = newMouseTerminalEvent(eventName, mouse, targetId)
  ev.kind = case eventName
           of "mousedown": ekMouseDown
           of "mouseup":   ekMouseUp
           of "mousemove": ekMouseMove
           of "scroll":    ekScroll
           else:           ekMouseDown
  p.h.driver.injectEvent(ev)
  discard p.h.driver.readEvents()
  if targetId != 0 and p.h.root != nil:
    proc walk(n: TerminalNode) =
      if n == nil: return
      if n.id == targetId:
        fireEventWith(n, eventName, ev)
        return
      # Snapshot children before iterating: event listeners may mutate
      # the tree (mount modals, swap content panes, etc.) and we don't
      # want the iterator to fault when the seq grows mid-walk.
      var snapshot = newSeq[TerminalNode](n.children.len)
      for i in 0 ..< n.children.len: snapshot[i] = n.children[i]
      for c in snapshot: walk(c)
    walk(p.h.root)
  p.h.recordEvent(targetId, eventName)
  p.h.flush()

# ----------------------------------------------------------------------------
# Press / Type
# ----------------------------------------------------------------------------

proc parseKeyName(keyStr: string): tuple[name: string; rune: uint32;
                                         mods: set[Modifier];
                                         kind: KeyKind] =
  ## Translate Textual-style key strings (`enter`, `tab`, `ctrl+c`,
  ## `f1`, `a`) into the structured fields the event expects.
  result.mods = {}
  if '+' in keyStr:
    let parts = keyStr.split('+')
    for i in 0 ..< parts.len - 1:
      case parts[i].toLowerAscii
      of "ctrl": result.mods.incl modCtrl
      of "shift": result.mods.incl modShift
      of "alt": result.mods.incl modAlt
      of "meta", "cmd": result.mods.incl modMeta
      of "super": result.mods.incl modSuper
      else: discard
    result.name = parts[^1]
  else:
    result.name = keyStr
  let lower = result.name.toLowerAscii
  case lower
  of "enter", "return", "escape", "esc", "tab", "backspace", "delete",
     "space":
    result.kind = kkNamed
    if lower == "space":
      result.rune = uint32(' '.ord)
  of "up", "down", "left", "right", "home", "end", "pageup", "pagedown":
    result.kind = kkNavigation
  else:
    if lower.len >= 2 and lower[0] == 'f':
      var allDigits = true
      for c in lower[1 ..< lower.len]:
        if c notin '0'..'9': allDigits = false; break
      if allDigits:
        result.kind = kkFunction
        return
    if result.name.runeLen == 1:
      result.kind = kkChar
      result.rune = uint32(runeAt(result.name, 0).int32)
    else:
      result.kind = kkUnknown

proc press*(p: Pilot; keys: varargs[string]) =
  ## Emit a key event for each name in `keys`. Each press fires on the
  ## focused node (or the root, when nothing is focused) and triggers
  ## a flush. Parity with `Pilot.press`.
  ##
  ## `tab` / `shift+tab` are routed through the harness's focus manager
  ## first — so `Tab` advances focus through the chain even when
  ## individual widgets don't install their own keydown handlers for
  ## navigation.
  for k in keys:
    let parsed = parseKeyName(k)
    # Focus-manager hijack for Tab navigation.
    let lower = parsed.name.toLowerAscii
    if lower == "tab":
      if modShift in parsed.mods:
        discard p.h.focusPrev()
      else:
        discard p.h.focusNext()
      continue
    if lower == "shift+tab":
      discard p.h.focusPrev()
      continue
    let target = (if p.h.focusedId != 0: p.h.focusedId
                  else: (if p.h.root != nil: p.h.root.id else: 0))
    p.fireKeyEvent(target, "keydown", parsed.name, parsed.rune,
                    parsed.mods, parsed.kind)

proc `type`*(p: Pilot; text: string) =
  ## Emit one printable-character key event per Unicode codepoint.
  ## Mirrors `Pilot.type`: `pilot.type("hi")` produces 2 keydown events.
  for r in runes(text):
    let target = (if p.h.focusedId != 0: p.h.focusedId
                  else: (if p.h.root != nil: p.h.root.id else: 0))
    p.fireKeyEvent(target, "keydown", $r, uint32(r.int32),
                    {}, kkChar)

# Explicit alias for callers that prefer not to write `pilot.\`type\``.
proc typeText*(p: Pilot; text: string) {.inline.} = `type`(p, text)

# ----------------------------------------------------------------------------
# Click / hover / scroll
# ----------------------------------------------------------------------------

proc click*(p: Pilot; target: TerminalNode = nil; row: int = 0;
            col: int = 0; modifiers: set[Modifier] = {};
            button: MouseButton = mbLeft; times: int = 1) =
  let id = if target != nil: target.id else: 0
  for i in 0 ..< times:
    p.fireMouseEvent("mousedown",
                     newMouseEvent(button, row, col, modifiers), id)
    p.fireMouseEvent("mouseup",
                     newMouseEvent(button, row, col, modifiers), id)
    if target != nil:
      fireEvent(target, "click")
      p.h.recordEvent(id, "click")
      p.h.flush()

proc doubleClick*(p: Pilot; target: TerminalNode = nil;
                  row: int = 0; col: int = 0) =
  click(p, target, row, col, times = 2)

proc tripleClick*(p: Pilot; target: TerminalNode = nil;
                  row: int = 0; col: int = 0) =
  click(p, target, row, col, times = 3)

proc hover*(p: Pilot; target: TerminalNode = nil;
            row: int = 0; col: int = 0) =
  let id = if target != nil: target.id else: 0
  p.h.hoveredId = id
  p.fireMouseEvent("mousemove",
                   newMouseEvent(mbNone, row, col, {}), id)

proc mouseDown*(p: Pilot; target: TerminalNode = nil;
                row: int = 0; col: int = 0;
                button: MouseButton = mbLeft) =
  let id = if target != nil: target.id else: 0
  p.fireMouseEvent("mousedown",
                   newMouseEvent(button, row, col, {}), id)

proc mouseUp*(p: Pilot; target: TerminalNode = nil;
              row: int = 0; col: int = 0;
              button: MouseButton = mbLeft) =
  let id = if target != nil: target.id else: 0
  p.fireMouseEvent("mouseup",
                   newMouseEvent(button, row, col, {}), id)

proc scroll*(p: Pilot; target: TerminalNode = nil;
             dx: int = 0; dy: int = 0;
             row: int = 0; col: int = 0) =
  let id = if target != nil: target.id else: 0
  let button = if dy < 0: mbWheelUp
               elif dy > 0: mbWheelDown
               elif dx < 0: mbWheelLeft
               elif dx > 0: mbWheelRight
               else: mbNone
  p.fireMouseEvent("scroll",
                   newMouseEvent(button, row, col, {}), id)

# ----------------------------------------------------------------------------
# Focus / paste / resize
# ----------------------------------------------------------------------------

proc focus*(p: Pilot; target: TerminalNode = nil) =
  let id = if target != nil: target.id else: 0
  # Keep harness + focus manager in lockstep. The harness path also
  # fires blur on the previously-focused node (M12 contract).
  let prevId = p.h.focusedId
  p.h.focusedId = id
  if p.h.focusManager != nil:
    p.h.focusManager.focusedId = id
  if target != nil:
    var ev = TerminalEvent(kind: ekFocus, `type`: "focus", targetId: id,
                           currentTargetId: id)
    p.h.driver.injectEvent(ev)
    discard p.h.driver.readEvents()
    fireEventWith(target, "focus", ev)
    p.h.recordEvent(id, "focus")
  if prevId != 0 and prevId != id and p.h.root != nil:
    proc walk(n: TerminalNode): TerminalNode =
      if n == nil: return nil
      if n.id == prevId: return n
      for c in n.children:
        let m = walk(c)
        if m != nil: return m
      return nil
    let oldNode = walk(p.h.root)
    if oldNode != nil:
      var bev = TerminalEvent(kind: ekBlur, `type`: "blur",
                              targetId: prevId, currentTargetId: prevId)
      fireEventWith(oldNode, "blur", bev)
      p.h.recordEvent(prevId, "blur")
  p.h.flush()

proc paste*(p: Pilot; text: string; target: TerminalNode = nil) =
  let id = if target != nil: target.id
           else: (if p.h.focusedId != 0: p.h.focusedId else: 0)
  var ev = TerminalEvent(kind: ekPaste, `type`: "paste",
                          targetId: id, currentTargetId: id)
  ev.paste = PasteEvent(text: text)
  p.h.driver.injectEvent(ev)
  discard p.h.driver.readEvents()
  if target != nil:
    fireEventWith(target, "paste", ev)
  p.h.recordEvent(id, "paste")
  p.h.flush()

proc resize*(p: Pilot; cols, rows: int) =
  p.h.resize(cols, rows)
  p.h.recordEvent(0, "resize")

# ----------------------------------------------------------------------------
# Time / waiting
# ----------------------------------------------------------------------------

proc pause*(p: Pilot; delayMs: int = 0) =
  ## Move the virtual clock forward by `delayMs` and flush. Parity with
  ## `Pilot.pause`.
  p.h.advance(delayMs)

proc waitFor*(p: Pilot; predicate: proc(): bool;
              timeoutMs: int = 1000; stepMs: int = 10): bool =
  ## Step the virtual clock in `stepMs` increments until the predicate
  ## is true or `timeoutMs` elapses. No real wall-clock sleep occurs.
  if predicate(): return true
  var elapsed = 0
  while elapsed < timeoutMs:
    p.h.advance(stepMs)
    elapsed += stepMs
    if predicate(): return true
  return false

proc waitForAnimation*(p: Pilot) =
  ## Drive the virtual clock forward, in 1-frame increments, until the
  ## animator reports no active animations. Each tick processes one
  ## frame's worth of clock-scheduled callbacks and advances any
  ## active animation. Real wall-clock time does not pass.
  if p.h.animator == nil: return
  discard p.h.animator.waitForIdle(advanceClock = true)
  p.h.flush()

proc waitForScheduledAnimations*(p: Pilot) =
  ## Same as `waitForAnimation` for the M7 surface — Textual splits
  ## "scheduled but not yet running" from "running" via timers; under
  ## the unified clock model both share the same active set.
  if p.h.animator == nil: return
  discard p.h.animator.waitForIdle(advanceClock = true)
  p.h.flush()

proc exit*(p: Pilot; resultValue: int = 0): PilotResult =
  PilotResult(exited: true, value: resultValue)
