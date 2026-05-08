## widgets/image.nim — Tier-2 `Image` widget (M14).
##
## First-class terminal-graphics widget. Consumes `nim_termctl`'s L3
## image-emit API: detects supported protocols at construction
## (Kitty / iTerm2 / Sixel / text-fallback) via
## `detectImageSupport()`, picks the best supported encoder, and
## emits the byte payload to the harness driver. Hot-reload of `src`
## triggers `deleteImage(oldId)` (Kitty) followed by a fresh
## emission.
##
## Tests can drive this without a real terminal: the harness's
## `bytesEmitted` records every `writeRaw` call, so assertions can
## check the protocol-specific opening sequence (`\x1b_G` for Kitty,
## `\x1b]1337` for iTerm2, etc.). For protocol selection in tests,
## `setSupportOverride()` lets the test pin the detection result.
##
## Layout: the widget reserves `widthCells × heightCells` of the
## terminal grid via blank cells; the actual graphics overlay is
## emitted as a write-out side-channel which a real terminal
## interprets as the image.
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import ../renderer
import ./borders
import nim_termctl/image as termctlImage

# ----------------------------------------------------------------------------
# Re-export the L3 types that callers need so user code can import
# `isonim_tui` and have `Image`, `ImageProtocols`, `detectImageSupport`,
# etc. without reaching into `nim_termctl` directly.
# ----------------------------------------------------------------------------

export termctlImage.Image, termctlImage.ImageId, termctlImage.ImageFormat,
       termctlImage.SourceFormat, termctlImage.ImagePlacement,
       termctlImage.ImageProtocols, termctlImage.detectImageSupport,
       termctlImage.drawImage, termctlImage.deleteImage,
       termctlImage.emitITerm2Inline, termctlImage.emitKittyChunked

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------

type
  ImageEmittedProtocol* = enum
    ipNone        ## Text fallback only.
    ipKitty
    ipITerm2
    ipSixel

  ImageWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    src*: termctlImage.Image
    placement*: termctlImage.ImagePlacement
    widthCells*: int
    heightCells*: int
    protocols*: termctlImage.ImageProtocols
    chosen*: ImageEmittedProtocol     ## Picked protocol for `src`.
    lastImageId*: termctlImage.ImageId
    nextImageId*: uint32              ## Counter for Kitty image ids.
    lastEmittedBytes*: string         ## Most recent emit payload (for tests).
    deleteSequence*: string           ## Most recent delete payload.

# ----------------------------------------------------------------------------
# Override hook so tests can pin the detected protocol set without
# mutating the host environment.
# ----------------------------------------------------------------------------

var imageSupportOverride {.threadvar.}: termctlImage.ImageProtocols
var imageSupportOverrideSet {.threadvar.}: bool

proc setSupportOverride*(p: termctlImage.ImageProtocols) =
  ## Pin the L3 capability detection to the given protocol set. Used
  ## by tests that want to exercise specific encoder paths.
  imageSupportOverride = p
  imageSupportOverrideSet = true

proc clearSupportOverride*() =
  imageSupportOverrideSet = false

proc detectSupport(): termctlImage.ImageProtocols =
  ## Capability detection that honours the test-set override.
  if imageSupportOverrideSet: return imageSupportOverride
  termctlImage.detectImageSupport()

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; color: string = "") =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc renderTree*(w: ImageWidget) =
  ## Reserve `widthCells x heightCells` cells in the layout. The
  ## actual graphics payload is emitted as a side-channel via
  ## `lastEmittedBytes`; tests inspect it to confirm protocol
  ## selection. The reserved area renders as `[image WxH]` in the
  ## text-fallback case and as blanks otherwise (so a real terminal
  ## sees an empty rectangle the graphics layer fills in).
  let r = w.renderer
  clearTreeChildren(r, w.node)
  if w.chosen == ipNone:
    let label = "[image " & $w.widthCells & "x" & $w.heightCells & "]"
    let body = padOrTruncate(label, w.widthCells)
    emitRow(r, w.node, body)
    for _ in 1 ..< w.heightCells:
      emitRow(r, w.node, spaces(w.widthCells))
  else:
    for _ in 0 ..< w.heightCells:
      emitRow(r, w.node, spaces(w.widthCells))

# ----------------------------------------------------------------------------
# Protocol selection
# ----------------------------------------------------------------------------

proc pickProtocol(p: termctlImage.ImageProtocols;
                  preferred: termctlImage.ImageFormat
                  ): ImageEmittedProtocol =
  ## Mirror of nim_termctl's drawImage selection logic. Caller's
  ## preferred encoder wins iff supported; otherwise we fall back in
  ## the order Kitty > iTerm2 > Sixel > none.
  case preferred
  of termctlImage.ifKitty:
    if p.kitty: return ipKitty
  of termctlImage.ifITerm2:
    if p.iterm2: return ipITerm2
  of termctlImage.ifSixel:
    if p.sixel: return ipSixel
  of termctlImage.ifAuto:
    discard
  if p.kitty:  return ipKitty
  if p.iterm2: return ipITerm2
  if p.sixel:  return ipSixel
  ipNone

# ----------------------------------------------------------------------------
# Emission
# ----------------------------------------------------------------------------

proc emitImage(w: ImageWidget): string =
  ## Build (but don't yet write) the protocol-specific byte sequence
  ## for the current `src`.
  case w.chosen
  of ipKitty:
    let id = uint32(w.lastImageId)
    try:
      return termctlImage.emitKittyChunked(w.src, id)
    except termctlImage.ImageNotImplementedDefer:
      # Sixel/RGBA passthrough not shipped yet — caller will fall back.
      return ""
  of ipITerm2:
    return termctlImage.emitITerm2Inline(w.src)
  of ipSixel:
    try:
      return termctlImage.emitSixel(w.src)
    except termctlImage.ImageNotImplementedDefer:
      return ""
  of ipNone:
    return ""

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newImageWidget*(renderer: TerminalRenderer;
                     src: termctlImage.Image;
                     widthCells: int = 8;
                     heightCells: int = 4;
                     placement: termctlImage.ImagePlacement =
                       termctlImage.ImagePlacement()): ImageWidget =
  let node = renderer.createElement("div")
  renderer.setAttribute(node, "data-widget", "image")
  renderer.setAttribute(node, "class", "image")
  let p = detectSupport()
  let chosen = pickProtocol(p, src.preferredFormat)
  let w = ImageWidget(
    renderer: renderer, node: node,
    src: src, placement: placement,
    widthCells: max(1, widthCells),
    heightCells: max(1, heightCells),
    protocols: p, chosen: chosen,
    lastImageId: termctlImage.ImageId(0),
    nextImageId: 1,
    lastEmittedBytes: "",
    deleteSequence: "")
  renderer.setAttribute(node, "data-protocol", $chosen)
  w.renderTree()
  # Initial emit so the side-channel byte stream reflects mount.
  if chosen == ipKitty:
    w.lastImageId = termctlImage.ImageId(w.nextImageId)
    inc w.nextImageId
  w.lastEmittedBytes = w.emitImage()
  w

# ----------------------------------------------------------------------------
# Hot-reload of `src`
# ----------------------------------------------------------------------------

proc setSrc*(w: ImageWidget; newSrc: termctlImage.Image) =
  ## Replace the source image. For Kitty, emit a delete-by-id for the
  ## previously-emitted image, then emit a fresh chunk. For iTerm2 and
  ## Sixel, emit the new bytes directly (those protocols have no
  ## persistent registry the way Kitty does).
  if w.chosen == ipKitty and uint32(w.lastImageId) != 0:
    w.deleteSequence = termctlImage.deleteImage(w.lastImageId)
  else:
    w.deleteSequence = ""
  w.src = newSrc
  let p = detectSupport()
  w.protocols = p
  w.chosen = pickProtocol(p, newSrc.preferredFormat)
  w.renderer.setAttribute(w.node, "data-protocol", $w.chosen)
  if w.chosen == ipKitty:
    w.lastImageId = termctlImage.ImageId(w.nextImageId)
    inc w.nextImageId
  else:
    w.lastImageId = termctlImage.ImageId(0)
  w.lastEmittedBytes = w.emitImage()
  w.renderTree()

# ----------------------------------------------------------------------------
# Test introspection helpers
# ----------------------------------------------------------------------------

proc emittedBytes*(w: ImageWidget): string {.inline.} = w.lastEmittedBytes
proc deleteBytes*(w: ImageWidget): string {.inline.} = w.deleteSequence
proc protocol*(w: ImageWidget): ImageEmittedProtocol {.inline.} = w.chosen
proc currentImageId*(w: ImageWidget): termctlImage.ImageId {.inline.} =
  w.lastImageId

proc imageHash*(w: ImageWidget): uint64 =
  ## Stable hash over `src.bytes` so tests can compare an image's
  ## logical content across protocol selections.
  var h: uint64 = 14695981039346656037'u64
  for b in w.src.bytes:
    h = (h xor uint64(b)) * 1099511628211'u64
  h

proc id*(w: ImageWidget): int {.inline.} = w.node.id
