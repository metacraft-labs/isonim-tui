## Terminal event types for isonim-tui.
##
## These are *value-typed* events designed to flow through the renderer
## without heap allocation. They mirror `isonim/src/isonim/web/dom_api.nim`
## (lines 32-38) for shape parity — `type`, `target`, `currentTarget`,
## `defaultPrevented`, `propagationStopped` — so application code that
## destructures events compiles unchanged across renderers.
##
## Charter §1: no `ref object` in public API. The element handle the
## `target` field carries is opaque (`int` node id) so the event itself
## stays a plain value object with copy-able semantics.
##
## Later milestones layer richer key/mouse decoding on top (the wire-level
## XTerm parser is L3's `nim-termctl` job; this module is the renderer-side
## representation).

import std/sets

type
  Modifier* = enum
    ## Keyboard / mouse modifier flags. Values match Textual's
    ## `events.MouseDown.modifiers` shape (no shift/ctrl-as-string
    ## fall-through). They are stored as a `set[Modifier]` so unioning
    ## multiple modifiers is O(1) and value-copyable.
    modShift
    modAlt
    modCtrl
    modMeta       ## Cmd on macOS, Win key on Windows
    modHyper      ## Reserved for keyboards with the extra modifier
    modSuper

  KeyKind* = enum
    ## Coarse key classification. The `key` string carries the canonical
    ## Textual key name (`"enter"`, `"f5"`, `"shift+a"`, `"a"`); `kind`
    ## tells consumers whether to inspect `key` as a printable rune or a
    ## named key.
    kkChar        ## A printable Unicode codepoint (single grapheme)
    kkNamed       ## A named key like `"enter"`, `"escape"`, `"tab"`
    kkFunction    ## Function keys f1..f24
    kkNavigation  ## Arrow keys, home/end/pgup/pgdn
    kkUnknown     ## Anything the parser couldn't classify

  MouseButton* = enum
    mbNone
    mbLeft
    mbMiddle
    mbRight
    mbWheelUp
    mbWheelDown
    mbWheelLeft
    mbWheelRight
    mbBack
    mbForward

  EventKind* = enum
    ## Discriminator for the `TerminalEvent` variant. Mirrors Textual's
    ## `events.Event` taxonomy: key, mouse press/release, motion, scroll,
    ## resize, focus/blur, paste, plus a synthetic `ekCustom` slot the
    ## DSL uses for user-defined events.
    ekCustom
    ekKey
    ekMouseDown
    ekMouseUp
    ekMouseMove
    ekScroll
    ekResize
    ekFocus
    ekBlur
    ekPaste

  KeyEvent* = object
    ## Decoded key event. `rune` is 0 for non-character keys.
    kind*: KeyKind
    key*: string         ## Canonical Textual-style name, e.g. "enter", "a"
    rune*: uint32        ## Unicode codepoint when `kind == kkChar`, else 0
    modifiers*: set[Modifier]

  MouseEvent* = object
    ## Mouse button / motion / wheel event.
    button*: MouseButton
    row*: int            ## 0-based screen row
    col*: int            ## 0-based screen column
    modifiers*: set[Modifier]

  ResizeEvent* = object
    cols*: int
    rows*: int

  PasteEvent* = object
    text*: string

  TerminalEvent* = object
    ## Top-level event delivered to handlers registered via
    ## `addEventListener`. The shape mirrors `dom_api.Event` so handlers
    ## written `(ev) => ev.target.something` work across renderers.
    ##
    ## Discriminator is `kind`. `key`, `mouse`, `resize`, `paste` are
    ## populated based on `kind` (Nim variant objects would be more
    ## ergonomic but force callers to write `case ev.kind` instead of
    ## the more familiar `ev.key.rune` pattern; we stay flat for parity
    ## with `dom_api.Event`'s shape).
    kind*: EventKind
    `type`*: string         ## Textual event name, e.g. "click", "keydown"
    targetId*: int          ## TerminalNode id (0 = none/anonymous)
    currentTargetId*: int
    defaultPrevented*: bool
    propagationStopped*: bool
    key*: KeyEvent
    mouse*: MouseEvent
    resize*: ResizeEvent
    paste*: PasteEvent

# ----------------------------------------------------------------------------
# Construction helpers
# ----------------------------------------------------------------------------

proc preventDefault*(ev: var TerminalEvent) {.inline.} =
  ## Mirrors the DOM `preventDefault()` semantic.
  ev.defaultPrevented = true

proc stopPropagation*(ev: var TerminalEvent) {.inline.} =
  ## Mirrors the DOM `stopPropagation()` semantic.
  ev.propagationStopped = true

proc newKeyEvent*(key: string; rune: uint32 = 0;
                  modifiers: set[Modifier] = {};
                  kind: KeyKind = kkChar): KeyEvent {.inline.} =
  KeyEvent(kind: kind, key: key, rune: rune, modifiers: modifiers)

proc newMouseEvent*(button: MouseButton; row, col: int;
                    modifiers: set[Modifier] = {}): MouseEvent {.inline.} =
  MouseEvent(button: button, row: row, col: col, modifiers: modifiers)

proc newCustomEvent*(`type`: string; targetId: int = 0): TerminalEvent {.inline.} =
  ## Synthesises a synthetic custom event with the given type-name and
  ## target id. Used by `fireEvent(node, name)` to construct a default
  ## event for handlers registered with the event-arg overload.
  TerminalEvent(kind: ekCustom, `type`: `type`, targetId: targetId,
                currentTargetId: targetId)

proc newKeyTerminalEvent*(name: string; key: KeyEvent;
                          targetId: int = 0): TerminalEvent {.inline.} =
  TerminalEvent(kind: ekKey, `type`: name, targetId: targetId,
                currentTargetId: targetId, key: key)

proc newMouseTerminalEvent*(name: string; mouse: MouseEvent;
                            targetId: int = 0): TerminalEvent {.inline.} =
  TerminalEvent(kind: ekMouseDown, `type`: name, targetId: targetId,
                currentTargetId: targetId, mouse: mouse)

proc hasModifier*(ev: TerminalEvent; m: Modifier): bool {.inline.} =
  ## Convenience accessor: returns true if any of the event's payloads
  ## carries the given modifier. Saves callers from having to know which
  ## sub-record holds it.
  case ev.kind
  of ekKey: m in ev.key.modifiers
  of ekMouseDown, ekMouseUp, ekMouseMove, ekScroll: m in ev.mouse.modifiers
  else: false

# Sanity: make sure `set[Modifier]` round-trips through value semantics.
# (This is a quiet compile-time check — never instantiates at runtime.)
when not compiles((var s: HashSet[Modifier]; s.incl(modShift); s)):
  {.error: "Modifier must be a value enum usable in std/sets".}
