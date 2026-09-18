## isonim_tui/reconciler.nim
##
## NH-M3 — the TUI instance of IsoNim's ``RendererReconciler`` contract
## (``isonim/native/reconciler``).
##
## ## Why the TUI is the cheapest case, and what that does NOT mean
##
## The design doc grades TUI "lowest difficulty" because the compositor
## already diffs at cell level: even a worst-case "rebuild this subtree"
## repaints smoothly, so a bad reconciler here is invisible on screen.
##
## **That is exactly why the gate for it may not look at the screen.**
## The thing a reconciler preserves in a terminal is not pixels, which
## the compositor would reproduce either way — it is NODE IDENTITY, and
## with it the focus target, the selection, the scroll offset and the
## registered event handlers, all of which hang off the
## ``TerminalNode``. ``tests/test_tui_reconciler_identity.nim`` asserts
## on the node reference and on the ``ReconcileStats`` census for that
## reason.
##
## ## Identity
##
## The key lives in the ``data-isonim-key`` attribute, the same name the
## other instances use — the const is imported from
## ``isonim/native/reconciler_native`` rather than respelled here, so
## the four instances cannot drift onto four attribute names.
## Unkeyed nodes fall back to ``defaultIdentityKey(tag, index)``.

when defined(js):
  {.error: "isonim_tui/reconciler is for native (nim c) targets only.".}

import std/[tables, strutils]
import isonim_tui/renderer
import isonim/native/reconciler
import isonim/native/reconciler_native

export reconciler, IsonimKeyAttr

proc tuiIdentityKey*(n: TerminalNode; index: int): NodeIdentity =
  if n == nil: return ""
  if n.attributes.hasKey(IsonimKeyAttr):
    return n.attributes[IsonimKeyAttr]
  defaultIdentityKey(n.tag, index)

proc indexInParent(n: TerminalNode): int =
  if n == nil or n.parent == nil: return 0
  for i, c in n.parent.children:
    if c == n: return i
  0

proc newTuiReconciler*(): RendererReconciler[TerminalNode] =
  ## The reconciler for ``TerminalRenderer``'s tree.
  ##
  ## Every mutation goes through the RendererBackend ops rather than
  ## touching ``children`` directly: those ops maintain the ``parent``
  ## back-reference, and the TUI's hit-tester walks upward. A reconciler
  ## that edited the seq in place would leave a tree that paints
  ## correctly and routes clicks to the wrong widget.
  let r = TerminalRenderer()
  RendererReconciler[TerminalNode](
    nodes: RendererTreeNodeOps[TerminalNode](
      identityKey: proc(n: TerminalNode): NodeIdentity =
        tuiIdentityKey(n, indexInParent(n)),
      kind: proc(n: TerminalNode): NodeKind =
        if n == nil: "" else: $n.kind & ":" & n.tag,
      children: proc(n: TerminalNode): seq[TerminalNode] =
        if n == nil: @[] else: n.children,
      properties: proc(n: TerminalNode): Table[string, string] =
        result = initTable[string, string]()
        if n == nil: return
        for k, v in n.attributes:
          # The key is excluded: it is why these two nodes matched, not
          # a property of either, and including it would make every
          # positionally-keyed node that moved also report a prop change.
          if k != IsonimKeyAttr: result[k] = v
        for k, v in n.styles:
          result["style:" & k] = v
        if n.text.len > 0: result["text"] = n.text),
    placeAt: proc(parent, child: TerminalNode; index: int) =
      if parent == nil or child == nil: return
      if index >= parent.children.len:
        r.appendChild(parent, child)
      else:
        r.insertBefore(parent, child, parent.children[index]),
    move: proc(parent, child: TerminalNode; fromIndex, toIndex: int) =
      if parent == nil or child == nil: return
      r.removeChild(parent, child)
      if toIndex >= parent.children.len:
        r.appendChild(parent, child)
      else:
        r.insertBefore(parent, child, parent.children[toIndex]),
    remove: proc(parent, child: TerminalNode) =
      if parent == nil or child == nil: return
      r.removeChild(parent, child),
    updateProps: proc(node: TerminalNode;
                      oldProps, newProps: Table[string, string]) =
      if node == nil: return
      for k, v in newProps:
        if k == "text":
          if node.text != v: r.setTextContent(node, v)
        elif k.startsWith("style:"):
          r.setStyle(node, k["style:".len .. ^1], v)
        else:
          r.setAttribute(node, k, v)
      for k in oldProps.keys:
        if not newProps.hasKey(k):
          if k == "text":
            r.setTextContent(node, "")
          elif not k.startsWith("style:"):
            r.removeAttribute(node, k))
