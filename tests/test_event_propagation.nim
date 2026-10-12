## test_event_propagation — events that travel through the tree.
##
## `dispatchEvent` (capture, target and bubble phases; `stopPropagation`;
## `preventDefault`; `currentTargetId` and `phase` per listener), the focus
## manager's `focusPath`, `focusin` / `focusout` and token-checked focus
## traps — on real `TerminalNode` trees built by the production renderer and
## a real `TerminalTestHarness`. No stand-ins.

import std/[sequtils, unittest]
import isonim_tui

type Seen = seq[string]

proc tree(r: TerminalRenderer): tuple[root, pane, row: TerminalNode] =
  ## window ─ pane ─ row
  let root = r.createElement("div")
  let pane = r.createElement("div")
  let row = r.createElement("div")
  r.appendChild(root, pane)
  r.appendChild(pane, row)
  (root, pane, row)

proc record(r: TerminalRenderer; node: TerminalNode; name: string;
            seen: ref Seen; capture: bool; stop = false; prevent = false) =
  let handler: PropagatingHandler = proc(ev: var TerminalEvent) =
    seen[].add name & ":" & $ev.phase & ":" & $ev.currentTargetId
    if stop: ev.stopPropagation()
    if prevent: ev.preventDefault()
  r.addEventListener(node, "keydown", handler, capture)

suite "dispatchEvent":
  test "capture runs outermost first, then the target, then bubble innermost first":
    var r: TerminalRenderer
    let (root, pane, row) = tree(r)
    let seen = new Seen
    for (n, name) in [(root, "root"), (pane, "pane"), (row, "row")]:
      record(r, n, name & "-capture", seen, capture = true)
      record(r, n, name & "-bubble", seen, capture = false)
    var ev = newCustomEvent("keydown")
    check dispatchEvent(row, ev)
    check seen[] == @[
      "root-capture:capturing:" & $root.id,
      "pane-capture:capturing:" & $pane.id,
      "row-capture:at-target:" & $row.id,
      "row-bubble:at-target:" & $row.id,
      "pane-bubble:bubbling:" & $pane.id,
      "root-bubble:bubbling:" & $root.id]
    check ev.targetId == row.id
    check ev.phase == epNone
    check ev.currentTargetId == 0

  test "stopPropagation in the capture phase reaches neither target nor bubble":
    var r: TerminalRenderer
    let (root, pane, row) = tree(r)
    let seen = new Seen
    record(r, root, "root-capture", seen, capture = true)
    record(r, pane, "pane-capture", seen, capture = true, stop = true)
    record(r, row, "row", seen, capture = false)
    record(r, root, "root-bubble", seen, capture = false)
    var ev = newCustomEvent("keydown")
    discard dispatchEvent(row, ev)
    check seen[] == @["root-capture:capturing:" & $root.id,
                      "pane-capture:capturing:" & $pane.id]
    check ev.propagationStopped

  test "stopPropagation at the target ends the walk before bubbling":
    var r: TerminalRenderer
    let (root, _, row) = tree(r)
    let seen = new Seen
    record(r, row, "row", seen, capture = false, stop = true)
    record(r, root, "root", seen, capture = false)
    var ev = newCustomEvent("keydown")
    discard dispatchEvent(row, ev)
    check seen[] == @["row:at-target:" & $row.id]

  test "bubbles = false: capture and target only":
    var r: TerminalRenderer
    let (root, _, row) = tree(r)
    let seen = new Seen
    record(r, root, "root-capture", seen, capture = true)
    record(r, root, "root-bubble", seen, capture = false)
    record(r, row, "row", seen, capture = false)
    var ev = newCustomEvent("keydown")
    discard dispatchEvent(row, ev, bubbles = false)
    check seen[] == @["root-capture:capturing:" & $root.id,
                      "row:at-target:" & $row.id]

  test "preventDefault is the result, and the event keeps the flag":
    var r: TerminalRenderer
    let (root, _, row) = tree(r)
    let seen = new Seen
    record(r, root, "root", seen, capture = false, prevent = true)
    var ev = newCustomEvent("keydown")
    check not dispatchEvent(row, ev)
    check ev.defaultPrevented
    var other = newCustomEvent("keydown")
    check dispatchEvent(root.children[0], other) == false

  test "the DSL's handlers run at the target and bubble, on a copy":
    var r: TerminalRenderer
    let (root, pane, row) = tree(r)
    var order: seq[string] = @[]
    r.addEventListener(pane, "keydown", proc(ev: TerminalEvent) =
      order.add "pane-dsl:" & $ev.phase)
    r.addEventListener(row, "keydown", proc() = order.add "row-noarg")
    r.addEventListener(root, "keydown", proc(ev: TerminalEvent) =
      var copy = ev
      copy.stopPropagation()      # a copy: the walk does not see it
      order.add "root-dsl")
    var ev = newCustomEvent("keydown")
    discard dispatchEvent(row, ev)
    check order == @["row-noarg", "pane-dsl:bubbling", "root-dsl"]
    check not ev.propagationStopped

  test "a listener that moves the target does not change this event's path":
    var r: TerminalRenderer
    let (root, pane, row) = tree(r)
    let seen = new Seen
    let mover: PropagatingHandler = proc(ev: var TerminalEvent) =
      r.removeChild(pane, row)
      r.appendChild(root, row)
    r.addEventListener(row, "keydown", mover, false)
    record(r, pane, "pane", seen, capture = false)
    var ev = newCustomEvent("keydown")
    discard dispatchEvent(row, ev)
    check seen[] == @["pane:bubbling:" & $pane.id]

  test "a detached node is its own path":
    var r: TerminalRenderer
    let lone = r.createElement("div")
    check propagationPath(lone).mapIt(it.id) == @[lone.id]

suite "focus path, focusin / focusout":
  proc buttons(h: TerminalTestHarness): tuple[root, group, a, b: TerminalNode] =
    var res: tuple[root, group, a, b: TerminalNode]
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let group = r.createElement("div")
      let a = newButton(r, "A", width = 4).node
      let b = newButton(r, "B", width = 4).node
      r.appendChild(root, group)
      r.appendChild(group, a)
      r.appendChild(root, b)
      res = (root, group, a, b)
      root)
    res

  test "focusPath is the focused node's ancestors and itself, outermost first":
    let h = newTerminalTestHarness(20, 4)
    let (root, group, a, b) = buttons(h)
    check h.focusManager.focusPath(root).len == 0
    discard h.setFocus(a)
    check h.focusManager.focusPath(root) == @[root.id, group.id, a.id]
    discard h.setFocus(b)
    check h.focusManager.focusPath(root) == @[root.id, b.id]
    h.dispose()

  test "blur, focusout, focus, focusin — and only the two -in/-out bubble":
    let h = newTerminalTestHarness(20, 4)
    let (root, group, a, b) = buttons(h)
    discard h.setFocus(a)
    let seen = new Seen
    proc listenerFor(name: string): PropagatingHandler =
      result = proc(ev: var TerminalEvent) =
        seen[].add name & "@" & $ev.currentTargetId & " related=" &
                   $ev.relatedTargetId
    for n in ["blur", "focusout", "focus", "focusin"]:
      let listener = listenerFor(n)
      h.renderer.addEventListener(group, n, listener, false)
      h.renderer.addEventListener(a, n, listener, false)
      h.renderer.addEventListener(b, n, listener, false)
    discard h.setFocus(b)
    # `a` loses focus: blur on a (no bubble to the group), focusout on a and
    # then the group (it bubbles: the group learns focus left its subtree).
    # `b` gains it: focus, focusin (b is outside the group).
    check seen[] == @[
      "blur@" & $a.id & " related=" & $b.id,
      "focusout@" & $a.id & " related=" & $b.id,
      "focusout@" & $group.id & " related=" & $b.id,
      "focus@" & $b.id & " related=" & $a.id,
      "focusin@" & $b.id & " related=" & $a.id]
    discard root
    h.dispose()

suite "focus traps are popped by token":
  test "a mismatched pop changes nothing; the owner's pop works":
    let fm = newFocusManager()
    let t1 = fm.pushTrap(10)
    let t2 = fm.pushTrap(20)
    check fm.currentTrap == 20
    check not fm.popTrap(t1)              # not on top
    check fm.traps.mapIt(it.rootId) == @[10, 20]
    check fm.popTrap(t2)
    check fm.currentTrap == 10
    check not fm.popTrap(t2)              # already gone
    check fm.popTrap(t1)
    check fm.currentTrap == 0
    check fm.traps.len == 0

  test "tokens are never reused":
    let fm = newFocusManager()
    let t1 = fm.pushTrap(1)
    check fm.popTrap(t1)
    let t2 = fm.pushTrap(1)
    check not (t1 == t2)
    check not fm.popTrap(t1)
    check fm.currentTrap == 1
