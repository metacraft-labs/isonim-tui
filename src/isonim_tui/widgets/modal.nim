## widgets/modal.nim — Tier-2 `Modal` widget (M14).
##
## A first-class overlay layer. Modals open above the underlying tree
## via M8's compositor layer system (`layer = N >= 1`), trap focus
## inside their subtree via M12's `FocusManager.pushTrap`, animate
## entry / exit via the M7 animator, and return focus to the opener
## on close. `Escape` dismisses by default (Textual parity).
##
## Public API:
##
##   * `newModal(harness, title, content, opener)`
##   * `modal.open()` — installs the layer + trap, fires the entry animation,
##     focuses the first focusable inside.
##   * `modal.close()` — fires the exit animation, removes the layer +
##     trap, returns focus to `opener`.
##   * `modal.isOpen` / `modal.animation` — introspection.
##
## Charter §1: every public type is a value object; the modal handle
## is a `ref` so callers can mutate state directly.

import std/[strutils, tables]

import ../renderer
import ../events
import ../css/properties
import ../animation/animator
import ../animation/easing
import ../testing/harness
import ./borders

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  ModalState* = enum
    msClosed
    msOpening
    msOpen
    msClosing

  ModalWidget* = ref object
    h*: TerminalTestHarness
    node*: TerminalNode               ## The modal's outer overlay node.
    panel*: TerminalNode              ## Inner content panel (focus root).
    contentMount*: TerminalNode       ## User content lives here.
    title*: string
    width*: int
    height*: int
    layer*: int
    state*: ModalState
    opener*: TerminalNode             ## Where focus returns on close.
    animProgress*: float64            ## 0..1
    animDurationMs*: float64
    onClose*: proc()

# ----------------------------------------------------------------------------
# Forward declarations
# ----------------------------------------------------------------------------
proc renderTree*(m: ModalWidget)
proc open*(m: ModalWidget)
proc close*(m: ModalWidget)

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc renderTree*(m: ModalWidget) =
  ## Re-render the modal panel chrome (title bar + border). The content
  ## is mounted under `contentMount` and isn't touched here so callers
  ## can build arbitrary widget subtrees inside.
  let r = m.h.renderer
  let height = max(3, m.height)
  let width = max(4, m.width)
  let visibleRows =
    if m.state == msOpen: height
    elif m.state == msClosed: 0
    else: max(0, int(height.float64 * m.animProgress))

  # Set styles on outer node — `layer` puts the modal above the base
  # tree; background-color makes the layer opaque.
  r.setStyle(m.node, "layer", $m.layer)
  r.setStyle(m.node, "background-color", "blue")
  r.setStyle(m.node, "color", "white")

  # The panel is a child of the modal node. We rebuild its top
  # decorations on every renderTree, but leave `contentMount` alive so
  # user widgets persist across paints.
  while m.panel.children.len > 0:
    if m.panel.children[0] == m.contentMount: break
    r.removeChild(m.panel, m.panel.children[0])

  if visibleRows >= 1:
    let glyphs = bordersGlyphs(bsRound)
    let titleBar = m.title
    let titleRow =
      if titleBar.len > 0:
        let centered = padOrTruncate(titleBar, width - 2)
        glyphs.left & centered & glyphs.right
      else:
        glyphs.left & spaces(width - 2) & glyphs.right
    # Insert title bar at the top.
    let titleNode = r.createElement("div")
    r.setStyle(titleNode, "color", "white")
    r.appendChild(titleNode, r.createTextNode(topBorderRow(glyphs, width - 2)))
    r.insertBefore(m.panel, titleNode, m.contentMount)
    let titleNode2 = r.createElement("div")
    r.setStyle(titleNode2, "color", "white")
    r.appendChild(titleNode2, r.createTextNode(titleRow))
    r.insertBefore(m.panel, titleNode2, m.contentMount)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newModal*(h: TerminalTestHarness;
               title: string = "";
               width: int = 30;
               height: int = 8;
               layer: int = 10;
               animDurationMs: float64 = 200.0;
               onClose: proc() = nil): ModalWidget =
  ## Construct an unopened modal. The modal node is created but not
  ## attached to the harness's root; `open()` mounts it. The caller is
  ## responsible for adding content widgets under `modal.contentMount`.
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "modal")
  r.setAttribute(node, "class", "modal")
  let panel = r.createElement("div")
  r.setAttribute(panel, "data-widget", "modal-panel")
  r.setAttribute(panel, "data-focusable", "false")
  let mount = r.createElement("div")
  r.setAttribute(mount, "data-widget", "modal-content")
  r.appendChild(panel, mount)
  r.appendChild(node, panel)
  let m = ModalWidget(
    h: h, node: node, panel: panel, contentMount: mount,
    title: title, width: width, height: height,
    layer: layer, state: msClosed,
    opener: nil, animProgress: 0.0,
    animDurationMs: animDurationMs, onClose: onClose)
  m

# ----------------------------------------------------------------------------
# Open / close
# ----------------------------------------------------------------------------

proc focusFirstInside(m: ModalWidget) =
  ## Walk the panel subtree DFS pre-order; focus the first focusable
  ## descendant. Used on `open()` so the trap has a sensible initial
  ## focus.
  proc walk(n: TerminalNode): TerminalNode =
    if n == nil: return nil
    if n != m.panel and n.attributes.getOrDefault("data-focusable") == "true" and
       n.attributes.getOrDefault("disabled") == "":
      return n
    for c in n.children:
      let r = walk(c)
      if r != nil: return r
    nil
  let target = walk(m.panel)
  if target != nil:
    discard m.h.setFocus(target)

proc open*(m: ModalWidget) =
  if m.state in {msOpen, msOpening}: return
  m.state = msOpening
  m.opener = m.h.focusedNode
  if m.h.root != nil:
    m.h.renderer.appendChild(m.h.root, m.node)
  m.h.focusManager.pushTrap(m.panel.id)
  m.animProgress = 0.0
  m.renderTree()
  m.h.flush()

  # Animate `progress` 0→1 over animDurationMs with out_cubic.
  m.h.animator.animateFloat(
    targetId = m.node.id,
    attribute = "modal-open",
    startValue = 0.0,
    endValue = 1.0,
    durationMs = m.animDurationMs,
    easingFn = easeOutCubic,
    setter = proc(v: float64) =
      m.animProgress = v
      m.renderTree()
      m.h.flush(),
    onComplete = proc() =
      m.state = msOpen
      m.animProgress = 1.0
      m.renderTree()
      m.focusFirstInside()
      m.h.flush())

proc close*(m: ModalWidget) =
  if m.state in {msClosed, msClosing}: return
  m.state = msClosing
  m.h.animator.animateFloat(
    targetId = m.node.id,
    attribute = "modal-close",
    startValue = m.animProgress,
    endValue = 0.0,
    durationMs = m.animDurationMs,
    easingFn = easeOutCubic,
    setter = proc(v: float64) =
      m.animProgress = v
      m.renderTree()
      m.h.flush(),
    onComplete = proc() =
      m.state = msClosed
      m.h.focusManager.popTrap()
      if m.h.root != nil and m.node.parent != nil:
        m.h.renderer.removeChild(m.h.root, m.node)
      if m.opener != nil:
        discard m.h.setFocus(m.opener)
      else:
        m.h.focusedId = 0
      if m.onClose != nil: m.onClose()
      m.h.flush())

proc isOpen*(m: ModalWidget): bool {.inline.} =
  m.state in {msOpening, msOpen, msClosing}

proc id*(m: ModalWidget): int {.inline.} = m.node.id

# ----------------------------------------------------------------------------
# Escape-key handler — apps mount this on the harness root.
# ----------------------------------------------------------------------------

proc installEscapeHandler*(m: ModalWidget) =
  ## Convenience: install a keydown handler on the modal's panel that
  ## closes the modal when `Escape` is pressed. Apps that prefer to
  ## intercept Escape themselves can skip this and dispatch close()
  ## from their own handler.
  m.h.renderer.addEventListener(m.panel, "keydown",
    proc(ev: TerminalEvent) =
      if ev.kind != ekKey: return
      let lower = ev.key.key.toLowerAscii
      if lower == "escape" or lower == "esc":
        m.close())
