## widgets/input.nim — Tier-1c `Input` widget (M13).
##
## Port of `textual/widgets/_input.py` + `textual/widgets/input.py`.
## A single-line text input with cursor, selection, password masking,
## validation, suggestion, and a placeholder. Cursor and selection
## arithmetic are over **grapheme clusters** (M1's iterator) — never
## bytes — so `Backspace` deletes one user-perceived glyph (a ZWJ
## family is one cluster), not one UTF-8 byte.
##
## Default keybindings (mirrors `_input.py`'s BINDINGS):
##   * `Left` / `Right`               — cursor by one grapheme cluster
##   * `Shift+Left` / `Shift+Right`   — extend selection by one cluster
##   * `Home` / `Ctrl+A`              — go to start
##   * `End`  / `Ctrl+E`              — go to end
##   * `Shift+Home` / `Shift+End`     — extend selection to start/end
##   * `Ctrl+Shift+A`                 — select all
##   * `Backspace`                    — delete cluster left (or selection)
##   * `Delete` / `Ctrl+D`            — delete cluster right (or selection)
##   * `Ctrl+W`                       — delete word left
##   * `Ctrl+U`                       — delete to start
##   * `Ctrl+K`                       — delete to end
##   * `Enter`                        — submit (fires `submitted`)
##   * any printable character        — insert (replaces selection if any)
##
## Charter §1: every public type is a value object; the widget handle
## is a `ref` so callers can mutate state directly.

import std/[strutils, unicode]

import ../renderer
import ../events
import ../css/properties
import ../text/width as widthMod
import ./borders

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  Selection* = object
    ## Half-open selection over grapheme-cluster boundary indices.
    ## When `anchor == cursor`, the selection is empty and only the
    ## cursor is visible. Both fields are *cluster indices* into the
    ## widget's value string — 0 means "before the first cluster",
    ## N (= cluster count) means "after the last cluster". The byte
    ## offset for index i is `boundaries[i]` (see `boundariesFor`).
    anchor*: int
    cursor*: int

  ValidatorProc* = proc(value: string): bool {.closure.}
  SuggestionProc* = proc(value: string): string {.closure.}

  InputWidget* = ref object
    renderer*: TerminalRenderer
    node*: TerminalNode
    value*: string                     ## Current text content (raw).
    placeholder*: string               ## Shown when value is empty.
    password*: bool                    ## When true, display "•" per cluster.
    disabled*: bool
    width*: int                        ## Inner width in cells.
    border*: BorderStyle
    borderColor*: string
    selection*: Selection              ## Cursor + selection over clusters.
    validator*: ValidatorProc          ## Optional value-level validator.
    isValid*: bool                     ## Result of last validation pass.
    suggester*: SuggestionProc         ## Optional autocompletion proc.
    suggestion*: string                ## Last suggestion (for rendering).
    onChange*: proc(newValue: string)  ## Fired after every value mutation.
    onSubmit*: proc(value: string)     ## Fired on `Enter`.
    maxLength*: int                    ## 0 = no limit.

# Forward declarations for procs referenced inside the keydown closure.
proc renderTree*(w: InputWidget)
proc setValue*(w: InputWidget; newValue: string)
proc moveCursor*(w: InputWidget; toClusterIdx: int; selecting: bool = false)
proc deleteSelection(w: InputWidget): bool
proc insertText*(w: InputWidget; text: string)
proc submit*(w: InputWidget)
proc selectAll*(w: InputWidget)

# ----------------------------------------------------------------------------
# Grapheme-cluster boundary helpers
# ----------------------------------------------------------------------------

proc clusterBoundaries(s: string): seq[int] =
  ## Return the list of byte boundaries for `s`. The result has length
  ## `clusterCount + 1`. `result[0] == 0`; `result[^1] == s.len`. Index
  ## `i` corresponds to "the position just before cluster i" (or "just
  ## after the last cluster" when `i == clusterCount`).
  result = @[0]
  for c in graphemeClusters(s):
    result.add c.stop

proc clusterCount(s: string): int =
  result = 0
  for _ in graphemeClusters(s):
    inc result

proc clusterTextAt(s: string; idx: int): string =
  ## Substring of cluster index `idx` (0-based). Empty string if out of
  ## range. O(N) — fine because inputs are short.
  var i = 0
  for c in graphemeClusters(s):
    if i == idx: return c.text
    inc i
  return ""

proc clamp(v, lo, hi: int): int {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

proc selStart(w: InputWidget): int {.inline.} =
  min(w.selection.anchor, w.selection.cursor)

proc selEnd(w: InputWidget): int {.inline.} =
  max(w.selection.anchor, w.selection.cursor)

proc hasSelection*(w: InputWidget): bool {.inline.} =
  w.selection.anchor != w.selection.cursor

proc cursorPos*(w: InputWidget): int {.inline.} =
  w.selection.cursor

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------

proc runValidation(w: InputWidget) =
  if w.validator == nil:
    w.isValid = true
    return
  w.isValid = w.validator(w.value)
  if w.isValid:
    w.renderer.removeAttribute(w.node, "data-invalid")
    w.renderer.setAttribute(w.node, "class", "input")
  else:
    w.renderer.setAttribute(w.node, "data-invalid", "true")
    w.renderer.setAttribute(w.node, "class", "input -invalid")

proc runSuggester(w: InputWidget) =
  if w.suggester == nil or w.value.len == 0:
    w.suggestion = ""
    return
  let s = w.suggester(w.value)
  if s.len > w.value.len and s.startsWith(w.value):
    w.suggestion = s
  else:
    w.suggestion = ""

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearTreeChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string;
             color: string = "";
             reverse: bool = false;
             dim: bool = false) =
  let box = r.createElement("div")
  if color.len > 0:
    r.setStyle(box, "color", color)
  if reverse:
    r.setStyle(box, "reverse", "true")
  if dim:
    r.setStyle(box, "italic", "true")    # placeholder hint via italic
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc displayValue(w: InputWidget): string =
  ## The text actually rendered: the value, or password mask, or
  ## placeholder when empty.
  if w.value.len == 0:
    return w.placeholder
  if w.password:
    var s = ""
    for _ in graphemeClusters(w.value):
      s.add "\xe2\x80\xa2"  # U+2022 BULLET
    return s
  return w.value

proc renderTree*(w: InputWidget) =
  ## Rebuild the visible children. The input occupies three rows when
  ## `border != bsNone`, one row otherwise. The middle row holds the
  ## (masked) text padded / truncated to `width` cells. Selection is
  ## conveyed by setting `reverse: true` on that row when active.
  let r = w.renderer
  clearTreeChildren(r, w.node)
  let glyphs = bordersGlyphs(w.border)
  let useBorder = w.border != bsNone
  if useBorder:
    emitRow(r, w.node, topBorderRow(glyphs, w.width), w.borderColor)

  let isPlaceholder = w.value.len == 0 and w.placeholder.len > 0
  let body = padOrTruncate(displayValue(w), w.width)
  let textColor =
    if isPlaceholder: "default"
    else: ""
  let reverse = w.hasSelection()

  let rowText =
    if useBorder: glyphs.left & body & glyphs.right
    else: body
  emitRow(r, w.node, rowText, textColor, reverse, isPlaceholder)

  if useBorder:
    emitRow(r, w.node, bottomBorderRow(glyphs, w.width), w.borderColor)

# ----------------------------------------------------------------------------
# Cluster-cursor helpers
# ----------------------------------------------------------------------------

proc clusterCountValue(w: InputWidget): int {.inline.} =
  clusterCount(w.value)

proc clampCursor(w: InputWidget; idx: int): int {.inline.} =
  clamp(idx, 0, clusterCountValue(w))

proc moveCursor*(w: InputWidget; toClusterIdx: int; selecting: bool = false) =
  ## Set cursor to `toClusterIdx`. When `selecting`, keep the anchor in
  ## place so a selection range builds; otherwise collapse anchor to
  ## the new cursor position.
  let target = w.clampCursor(toClusterIdx)
  if selecting:
    w.selection.cursor = target
  else:
    w.selection.cursor = target
    w.selection.anchor = target
  w.renderTree()

proc selectAll*(w: InputWidget) =
  w.selection.anchor = 0
  w.selection.cursor = clusterCountValue(w)
  w.renderTree()

proc clearSelection*(w: InputWidget) =
  w.selection.anchor = w.selection.cursor
  w.renderTree()

# ----------------------------------------------------------------------------
# Mutators
# ----------------------------------------------------------------------------

proc applyValueChange(w: InputWidget; newValue: string;
                      newCursor: int) =
  let trimmed =
    if w.maxLength > 0 and clusterCount(newValue) > w.maxLength:
      # Truncate to maxLength clusters.
      var s = ""
      var i = 0
      for c in graphemeClusters(newValue):
        if i >= w.maxLength: break
        s.add c.text
        inc i
      s
    else:
      newValue
  let oldValue = w.value
  w.value = trimmed
  w.renderer.setAttribute(w.node, "value", trimmed)
  let n = clusterCountValue(w)
  let safeCursor = clamp(newCursor, 0, n)
  w.selection.cursor = safeCursor
  w.selection.anchor = safeCursor
  runValidation(w)
  runSuggester(w)
  w.renderTree()
  if oldValue != trimmed and w.onChange != nil:
    w.onChange(trimmed)

proc setValue*(w: InputWidget; newValue: string) =
  applyValueChange(w, newValue, clusterCount(newValue))

proc deleteSelection(w: InputWidget): bool =
  ## Remove the selected cluster range. Returns true if any chars were
  ## removed. Cursor lands at selection start.
  if not w.hasSelection(): return false
  let bounds = clusterBoundaries(w.value)
  let s = w.selStart
  let e = w.selEnd
  let byteStart = bounds[s]
  let byteEnd = bounds[e]
  let newVal = w.value[0 ..< byteStart] & w.value[byteEnd ..< w.value.len]
  applyValueChange(w, newVal, s)
  return true

proc insertText*(w: InputWidget; text: string) =
  ## Insert `text` at the cursor, replacing any active selection.
  if text.len == 0: return
  discard deleteSelection(w)
  let bounds = clusterBoundaries(w.value)
  let cur = w.selection.cursor
  let byteIns = bounds[cur]
  let prefix = w.value[0 ..< byteIns]
  let suffix = w.value[byteIns ..< w.value.len]
  let merged = prefix & text & suffix
  let insertedClusters = clusterCount(text)
  applyValueChange(w, merged, cur + insertedClusters)

proc backspace*(w: InputWidget) =
  ## Delete the cluster left of the cursor, or the active selection.
  if deleteSelection(w): return
  let cur = w.selection.cursor
  if cur == 0: return
  let bounds = clusterBoundaries(w.value)
  let byteStart = bounds[cur - 1]
  let byteEnd = bounds[cur]
  let newVal = w.value[0 ..< byteStart] & w.value[byteEnd ..< w.value.len]
  applyValueChange(w, newVal, cur - 1)

proc deleteRight*(w: InputWidget) =
  ## Delete the cluster right of the cursor, or the active selection.
  if deleteSelection(w): return
  let cur = w.selection.cursor
  let n = clusterCountValue(w)
  if cur >= n: return
  let bounds = clusterBoundaries(w.value)
  let byteStart = bounds[cur]
  let byteEnd = bounds[cur + 1]
  let newVal = w.value[0 ..< byteStart] & w.value[byteEnd ..< w.value.len]
  applyValueChange(w, newVal, cur)

proc deleteToStart*(w: InputWidget) =
  ## Ctrl+U — drop everything left of the cursor.
  let cur = w.selection.cursor
  if cur == 0:
    discard deleteSelection(w)
    return
  let bounds = clusterBoundaries(w.value)
  let byteEnd = bounds[cur]
  let newVal = w.value[byteEnd ..< w.value.len]
  applyValueChange(w, newVal, 0)

proc deleteToEnd*(w: InputWidget) =
  ## Ctrl+K — drop everything right of the cursor.
  let cur = w.selection.cursor
  let bounds = clusterBoundaries(w.value)
  let byteStart = bounds[cur]
  let newVal = w.value[0 ..< byteStart]
  applyValueChange(w, newVal, cur)

proc isWordChar(s: string): bool =
  ## Cluster-level "word" predicate. Anything non-whitespace counts.
  if s.len == 0: return false
  for r in runes(s):
    if r == Rune(' '.ord) or r == Rune('\t'.ord) or r == Rune('\n'.ord):
      return false
  return true

proc deleteWordLeft*(w: InputWidget) =
  ## Ctrl+W — delete from the cursor back through the previous word.
  if deleteSelection(w): return
  let cur = w.selection.cursor
  if cur == 0: return
  let bounds = clusterBoundaries(w.value)
  # Walk back over whitespace, then over word characters.
  var i = cur
  while i > 0 and not isWordChar(clusterTextAt(w.value, i - 1)):
    dec i
  while i > 0 and isWordChar(clusterTextAt(w.value, i - 1)):
    dec i
  let byteStart = bounds[i]
  let byteEnd = bounds[cur]
  let newVal = w.value[0 ..< byteStart] & w.value[byteEnd ..< w.value.len]
  applyValueChange(w, newVal, i)

proc submit*(w: InputWidget) =
  if w.onSubmit != nil:
    w.onSubmit(w.value)
  fireEvent(w.node, "submitted")

# ----------------------------------------------------------------------------
# Key handler
# ----------------------------------------------------------------------------

proc handleKey(w: InputWidget; ev: TerminalEvent) =
  if w.disabled: return
  if ev.kind != ekKey: return
  let key = ev.key
  let name = key.key.toLowerAscii
  let mods = key.modifiers
  let shift = modShift in mods
  let ctrl  = modCtrl  in mods

  case name
  of "left":
    if w.hasSelection() and not shift:
      w.moveCursor(w.selStart)
    else:
      w.moveCursor(w.selection.cursor - 1, selecting = shift)
  of "right":
    if w.hasSelection() and not shift:
      w.moveCursor(w.selEnd)
    else:
      w.moveCursor(w.selection.cursor + 1, selecting = shift)
  of "home":
    w.moveCursor(0, selecting = shift)
  of "end":
    w.moveCursor(clusterCountValue(w), selecting = shift)
  of "backspace":
    w.backspace()
  of "delete":
    w.deleteRight()
  of "enter", "return":
    w.submit()
  else:
    # Ctrl+ key chords.
    if ctrl and shift and name == "a":
      w.selectAll()
      return
    if ctrl:
      case name
      of "a":
        w.moveCursor(0, selecting = false)
        return
      of "e":
        w.moveCursor(clusterCountValue(w), selecting = false)
        return
      of "u":
        w.deleteToStart()
        return
      of "w":
        w.deleteWordLeft()
        return
      of "k":
        w.deleteToEnd()
        return
      of "d":
        w.deleteRight()
        return
      else: discard
      # Other ctrl combos: don't insert as text.
      return
    # Printable insertion. Skip when alt or meta is held (those are
    # action chords, not text input).
    if modAlt in mods or modMeta in mods: return
    if key.kind == kkChar and key.rune >= 0x20'u32 and key.rune != 0x7F'u32:
      let r = Rune(key.rune.int32)
      var s = ""
      s.add $r
      w.insertText(s)

# ----------------------------------------------------------------------------
# Construction
# ----------------------------------------------------------------------------

proc newInput*(renderer: TerminalRenderer;
               value: string = "";
               placeholder: string = "";
               password: bool = false;
               width: int = 20;
               border: BorderStyle = bsRound;
               borderColor: string = "";
               disabled: bool = false;
               maxLength: int = 0;
               validator: ValidatorProc = nil;
               suggester: SuggestionProc = nil;
               onChange: proc(newValue: string) = nil;
               onSubmit: proc(value: string) = nil): InputWidget =
  ## Construct an input. Mount it under a parent via
  ## `r.appendChild(parent, w.node)`. The value defaults to empty;
  ## passing a non-empty `value` parks the cursor at the end.
  let actualWidth = max(1, width)
  let node = renderer.createElement("input")
  renderer.setAttribute(node, "data-widget", "input")
  renderer.setAttribute(node, "data-focusable", "true")
  renderer.setAttribute(node, "class", "input")
  if disabled:
    renderer.setAttribute(node, "disabled", "true")
    renderer.setAttribute(node, "data-focusable", "false")
  if password:
    renderer.setAttribute(node, "data-password", "true")
  let w = InputWidget(
    renderer: renderer, node: node,
    value: "", placeholder: placeholder, password: password,
    disabled: disabled, width: actualWidth,
    border: border, borderColor: borderColor,
    selection: Selection(anchor: 0, cursor: 0),
    validator: validator, isValid: true,
    suggester: suggester, suggestion: "",
    onChange: onChange, onSubmit: onSubmit,
    maxLength: maxLength)
  if value.len > 0:
    w.value = value
    renderer.setAttribute(node, "value", value)
    w.selection = Selection(anchor: clusterCount(value),
                            cursor: clusterCount(value))
  runValidation(w)
  runSuggester(w)
  w.renderTree()

  renderer.addEventListener(node, "keydown", proc(ev: TerminalEvent) =
    w.handleKey(ev))
  renderer.addEventListener(node, "click", proc(ev: TerminalEvent) =
    if w.disabled: return
    discard)
  w

# ----------------------------------------------------------------------------
# Mutators / accessors used by tests
# ----------------------------------------------------------------------------

proc setPassword*(w: InputWidget; password: bool) =
  w.password = password
  if password:
    w.renderer.setAttribute(w.node, "data-password", "true")
  else:
    w.renderer.removeAttribute(w.node, "data-password")
  w.renderTree()

proc setPlaceholder*(w: InputWidget; placeholder: string) =
  w.placeholder = placeholder
  w.renderTree()

proc setDisabled*(w: InputWidget; disabled: bool) =
  w.disabled = disabled
  if disabled:
    w.renderer.setAttribute(w.node, "disabled", "true")
    w.renderer.setAttribute(w.node, "data-focusable", "false")
  else:
    w.renderer.removeAttribute(w.node, "disabled")
    w.renderer.setAttribute(w.node, "data-focusable", "true")

proc cursorCellOffset*(w: InputWidget): int =
  ## Cell-column offset of the cursor inside the inner text region.
  ## Sums grapheme-cluster widths up to `cursor`.
  result = 0
  var i = 0
  for c in graphemeClusters(w.value):
    if i >= w.selection.cursor: break
    result += clusterDisplayWidth(c.text)
    inc i

proc id*(w: InputWidget): int {.inline.} = w.node.id
