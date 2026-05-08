## command/palette.nim — Command Palette (M16).
##
## Port of `textual/command.py` (~1,286 LOC). Textual's signature
## feature: a modal full-screen overlay that opens on `Ctrl+\`, lets
## the user type a query, runs it through every registered `Provider`'s
## fuzzy matcher, and lists `Hit`s ranked by score. Selecting a hit
## (Enter) invokes its callback and closes the palette; Escape
## dismisses without running anything.
##
## We adopt the two-layer architecture from Textual:
##
##   1. `Provider` — abstract base. Each provider exposes `search(query)`
##      yielding `Hit`s. Providers can be registered with the palette.
##   2. `CommandPalette` — the modal widget. Holds an `Input` for the
##      query, a `ListView`-style result panel, and a list of registered
##      providers. Reacts to keydown to filter / select / dismiss.
##
## Built-in providers:
##
##   * `newSimpleProvider(name, commands)` — a `Hit` per static
##     `(text, callback)` pair. Used by app commands and by the
##     palette's introspection mode.
##   * `newSwitchScreenProvider(...)` — registers a hit per known
##     screen/route name.
##   * `newSwitchThemeProvider(reg)` — registers a hit per registered
##     theme; selecting one calls `reg.setTheme(name)`.
##
## The palette uses the M14 `Modal` infrastructure for layering and
## focus trapping. The default keybinding is `Ctrl+\`; it's installed
## via `palette.installGlobalBinding(harness)`.
##
## Charter §1: every public type is a value object; `CommandPalette`
## itself is a `ref` because it owns mutable widget state. The
## `Hit` and `DiscoveryHit` dataclasses are value objects with no
## refs.

import std/[algorithm, strutils]

import ../renderer
import ../events
import ../testing/harness
import ../theme/cascade
import ./fuzzy

# ----------------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------------

type
  CommandCallback* = proc() {.closure.}

  Hit* = object
    ## A single command-search hit. Mirrors `command.Hit` in Textual.
    ## `score` is the fuzzy score (higher is better); `matchDisplay`
    ## is the rendered string; `command` is the callback to run on
    ## selection; `text` is the plain-text label (used for sorting and
    ## introspection); `help` is an optional secondary description.
    score*: float64
    matchDisplay*: string
    command*: CommandCallback
    text*: string
    help*: string

  DiscoveryHit* = object
    ## Like `Hit` but for the empty-query "discovery" view. Score is
    ## fixed at 0; the order is whatever the provider yields.
    display*: string
    command*: CommandCallback
    text*: string
    help*: string

  ProviderKind* = enum
    ## Discriminator for `Provider`. We use a tagged-union value type
    ## rather than inheritance so providers can be stored cleanly in a
    ## `seq[Provider]`. `pkUser` is the escape hatch: a callback that
    ## returns its own `seq[Hit]` per query.
    pkSimple
    pkSwitchTheme
    pkUser

  ProviderSearchProc* = proc(query: string): seq[Hit] {.closure.}
  ProviderDiscoverProc* = proc(): seq[DiscoveryHit] {.closure.}

  Provider* = object
    ## A single registered command provider. Different providers
    ## populate hits from different sources — static command tables,
    ## theme registries, route maps, dynamic project state, etc.
    name*: string
    kind*: ProviderKind
    # `pkSimple`: static command table.
    simpleCommands*: seq[tuple[text, help: string;
                               command: CommandCallback]]
    # `pkSwitchTheme`: theme registry to switch.
    themeRegistry*: ThemeRegistry
    # `pkUser`: caller-supplied closures.
    searchProc*: ProviderSearchProc
    discoverProc*: ProviderDiscoverProc

  CommandPalette* = ref object
    ## The palette modal itself. Owns the input field, results list,
    ## and a registered list of providers. Constructed via
    ## `newCommandPalette(harness, providers)`.
    h*: TerminalTestHarness
    node*: TerminalNode               ## Outer modal/overlay node.
    inputNode*: TerminalNode          ## The query input element.
    resultsNode*: TerminalNode        ## Container that holds Hit rows.
    providers*: seq[Provider]
    isOpen*: bool
    opener*: TerminalNode             ## Where focus returns on close.
    query*: string                    ## Current query text.
    hits*: seq[Hit]                   ## Last-computed result list.
    selectedIdx*: int                 ## Highlighted row in `hits`.
    layer*: int                       ## Compositor layer (≥1).
    width*: int
    height*: int
    onClose*: proc()

# ----------------------------------------------------------------------------
# Hit construction
# ----------------------------------------------------------------------------

proc newHit*(score: float64; matchDisplay: string;
             command: CommandCallback; text: string = "";
             help: string = ""): Hit =
  let actualText = if text.len > 0: text else: matchDisplay
  Hit(score: score, matchDisplay: matchDisplay,
      command: command, text: actualText, help: help)

proc newDiscoveryHit*(display: string; command: CommandCallback;
                      text: string = ""; help: string = ""): DiscoveryHit =
  let actualText = if text.len > 0: text else: display
  DiscoveryHit(display: display, command: command,
               text: actualText, help: help)

# ----------------------------------------------------------------------------
# Hit comparison — descending by score, then by text
# ----------------------------------------------------------------------------

proc cmpHit*(a, b: Hit): int =
  if a.score > b.score: -1
  elif a.score < b.score: 1
  else: cmp(a.text, b.text)

proc cmpDiscoveryHit*(a, b: DiscoveryHit): int =
  cmp(a.text, b.text)

# ----------------------------------------------------------------------------
# Provider construction
# ----------------------------------------------------------------------------

proc newSimpleProvider*(name: string;
                        commands: openArray[tuple[text, help: string;
                                                  command: CommandCallback]]
                        ): Provider =
  ## Build a provider from a static set of `(text, help, callback)`
  ## tuples. Each becomes one `Hit` per query, scored by fuzzy match
  ## against `text`.
  var copied: seq[tuple[text, help: string; command: CommandCallback]] = @[]
  for c in commands: copied.add c
  Provider(name: name, kind: pkSimple, simpleCommands: copied)

proc makeThemeSetter(reg: ThemeRegistry; name: string): CommandCallback =
  ## Closure factory: each call returns a fresh closure capturing the
  ## supplied `name` argument by value. Inline construction inside a
  ## `for` loop falls foul of Nim's closure-over-loop-variable
  ## semantics (every closure ends up sharing the same `name` binding),
  ## so we build the closure in a sub-proc whose parameters create
  ## per-call locals.
  result = proc() {.closure.} =
    discard reg.setTheme(name)

proc newSwitchThemeProvider*(reg: ThemeRegistry;
                             prefix: string = "Switch theme: "): Provider =
  ## A provider whose hits are "Switch theme: <name>" for every
  ## registered theme. Selecting a hit calls `reg.setTheme(name)`.
  var commands: seq[tuple[text, help: string; command: CommandCallback]] = @[]
  for nm in reg.themeNames():
    commands.add (text: prefix & nm,
                  help: "Activate the " & nm & " theme",
                  command: makeThemeSetter(reg, nm))
  Provider(name: "Themes", kind: pkSwitchTheme,
           simpleCommands: commands, themeRegistry: reg)

proc newSwitchScreenProvider*(screens: openArray[tuple[name: string;
                                                       activate: CommandCallback]]
                             ): Provider =
  ## A provider whose hits are "Switch screen: <name>". Each screen
  ## carries an `activate` callback that mounts the screen.
  var commands: seq[tuple[text, help: string; command: CommandCallback]] = @[]
  for sc in screens:
    commands.add (text: "Switch screen: " & sc.name,
                  help: "Show the " & sc.name & " screen",
                  command: sc.activate)
  Provider(name: "Screens", kind: pkSimple, simpleCommands: commands)

proc newUserProvider*(name: string;
                      searchProc: ProviderSearchProc;
                      discoverProc: ProviderDiscoverProc = nil): Provider =
  ## An open-ended provider: the caller supplies the search closure.
  ## Used by tests and by application-specific providers (e.g. a
  ## project-wide command pool that consults runtime state).
  Provider(name: name, kind: pkUser,
           searchProc: searchProc, discoverProc: discoverProc)

# ----------------------------------------------------------------------------
# Provider search
# ----------------------------------------------------------------------------

proc searchProvider*(p: Provider; query: string): seq[Hit] =
  ## Return the provider's hits for `query`. For `pkSimple` and
  ## `pkSwitchTheme`, runs every command's `text` through the fuzzy
  ## matcher; entries with score ≤ 0 are dropped. For `pkUser`,
  ## delegates to the caller's closure.
  result = @[]
  case p.kind
  of pkSimple, pkSwitchTheme:
    let m = newMatcher(query)
    for c in p.simpleCommands:
      let s = m.match(c.text)
      if s > 0:
        result.add newHit(score = s, matchDisplay = c.text,
                          command = c.command, text = c.text, help = c.help)
  of pkUser:
    if p.searchProc != nil:
      result = p.searchProc(query)

proc discoverProvider*(p: Provider): seq[DiscoveryHit] =
  ## Return the provider's discovery hits (shown for the empty query).
  ## For static providers we surface every command, sorted by text.
  result = @[]
  case p.kind
  of pkSimple, pkSwitchTheme:
    for c in p.simpleCommands:
      result.add newDiscoveryHit(display = c.text, command = c.command,
                                 text = c.text, help = c.help)
  of pkUser:
    if p.discoverProc != nil:
      result = p.discoverProc()

# ----------------------------------------------------------------------------
# CommandPalette construction
# ----------------------------------------------------------------------------

proc renderTree*(cp: CommandPalette)
proc open*(cp: CommandPalette)
proc close*(cp: CommandPalette)
proc runQuery*(cp: CommandPalette)

proc newCommandPalette*(h: TerminalTestHarness;
                        providers: openArray[Provider] = [];
                        layer: int = 50;
                        width: int = 50;
                        height: int = 12;
                        onClose: proc() = nil): CommandPalette =
  ## Build the palette modal. The widget tree is created but **not**
  ## attached until `open()` mounts it as the harness's overlay layer.
  let r = h.renderer
  let node = r.createElement("div")
  r.setAttribute(node, "data-widget", "command-palette")
  r.setAttribute(node, "class", "command-palette")
  r.setAttribute(node, "data-focusable", "false")
  let inputNode = r.createElement("input")
  r.setAttribute(inputNode, "data-widget", "command-palette-input")
  r.setAttribute(inputNode, "data-focusable", "true")
  r.setAttribute(inputNode, "class", "command-palette-input")
  r.appendChild(node, inputNode)
  let resultsNode = r.createElement("div")
  r.setAttribute(resultsNode, "data-widget", "command-palette-results")
  r.appendChild(node, resultsNode)

  var copied: seq[Provider] = @[]
  for p in providers: copied.add p

  let cp = CommandPalette(
    h: h, node: node, inputNode: inputNode, resultsNode: resultsNode,
    providers: copied, isOpen: false, opener: nil,
    query: "", hits: @[], selectedIdx: 0,
    layer: layer, width: max(20, width), height: max(4, height),
    onClose: onClose)

  # The input's keydown listener handles every palette key event:
  #   Escape         — dismiss
  #   Enter / Return — run selected hit
  #   Up / Down      — move selection
  #   any printable  — append to query, re-search
  #   Backspace      — remove last query char, re-search
  r.addEventListener(inputNode, "keydown", proc(ev: TerminalEvent) =
    if not cp.isOpen: return
    if ev.kind != ekKey: return
    let lower = ev.key.key.toLowerAscii
    case lower
    of "escape", "esc":
      cp.close()
    of "enter", "return":
      if cp.selectedIdx >= 0 and cp.selectedIdx < cp.hits.len:
        let hit = cp.hits[cp.selectedIdx]
        # Close before running so the callback sees a clean focus
        # state (matches Textual semantics).
        cp.close()
        if hit.command != nil:
          hit.command()
    of "down":
      if cp.hits.len > 0:
        cp.selectedIdx = (cp.selectedIdx + 1) mod cp.hits.len
        cp.renderTree()
        cp.h.flush()
    of "up":
      if cp.hits.len > 0:
        cp.selectedIdx = (cp.selectedIdx - 1 + cp.hits.len) mod cp.hits.len
        cp.renderTree()
        cp.h.flush()
    of "backspace":
      if cp.query.len > 0:
        cp.query.setLen(cp.query.len - 1)
        cp.runQuery()
    else:
      # A printable character; append.
      if ev.key.kind == kkChar and ev.key.rune >= 0x20'u32 and
         ev.key.rune != 0x7F'u32:
        let r2 = ev.key.rune
        if r2 < 128:
          cp.query.add char(r2)
        else:
          # Multi-byte: pass-through via key.key string.
          cp.query.add ev.key.key
        cp.runQuery())
  cp

# ----------------------------------------------------------------------------
# Provider registration
# ----------------------------------------------------------------------------

proc registerProvider*(cp: CommandPalette; p: Provider) =
  cp.providers.add p

# ----------------------------------------------------------------------------
# Tree builder
# ----------------------------------------------------------------------------

proc clearChildren(r: TerminalRenderer; node: TerminalNode) =
  while node.children.len > 0:
    let c = node.children[0]
    r.removeChild(node, c)

proc emitRow(r: TerminalRenderer; parent: TerminalNode;
             text: string; reverse: bool = false; dim: bool = false) =
  let box = r.createElement("div")
  if reverse:
    r.setStyle(box, "reverse", "true")
  if dim:
    r.setStyle(box, "italic", "true")
  r.appendChild(box, r.createTextNode(text))
  r.appendChild(parent, box)

proc padOrTrunc(s: string; width: int): string =
  if s.len >= width: s[0 ..< width]
  else: s & " ".repeat(width - s.len)

proc renderTree*(cp: CommandPalette) =
  let r = cp.h.renderer
  # The query echoes inside the input node.
  clearChildren(r, cp.inputNode)
  let prompt = "> "
  let promptedQuery = prompt & cp.query
  emitRow(r, cp.inputNode, padOrTrunc(promptedQuery, cp.width))
  # The results list.
  clearChildren(r, cp.resultsNode)
  let visible = min(cp.hits.len, cp.height - 2)
  for i in 0 ..< visible:
    let h = cp.hits[i]
    let row = padOrTrunc("  " & h.matchDisplay, cp.width)
    emitRow(r, cp.resultsNode, row, reverse = (i == cp.selectedIdx))
  if cp.hits.len == 0 and cp.query.len > 0:
    emitRow(r, cp.resultsNode, padOrTrunc("  (no results)", cp.width),
            reverse = false, dim = true)
  # Set styles on outer node so the M8 compositor lifts the palette
  # above the base tree.
  r.setStyle(cp.node, "layer", $cp.layer)
  r.setStyle(cp.node, "background-color", "blue")
  r.setStyle(cp.node, "color", "white")
  r.setAttribute(cp.node, "data-open", $cp.isOpen)

# ----------------------------------------------------------------------------
# Querying
# ----------------------------------------------------------------------------

proc runQuery*(cp: CommandPalette) =
  ## Re-run every provider's `search(query)` (or `discover()` when the
  ## query is empty), merge results, sort by descending score, paint.
  cp.hits.setLen(0)
  if cp.query.len == 0:
    # Discovery: every provider's discovery list, surfaced as zero-score
    # Hits so the rest of the palette UI works uniformly.
    for p in cp.providers:
      for d in discoverProvider(p):
        cp.hits.add newHit(score = 0.0,
                           matchDisplay = d.display,
                           command = d.command,
                           text = d.text, help = d.help)
    cp.hits.sort(proc(a, b: Hit): int = cmp(a.text, b.text))
  else:
    for p in cp.providers:
      for h in searchProvider(p, cp.query):
        cp.hits.add h
    cp.hits.sort(cmpHit)
  cp.selectedIdx = if cp.hits.len > 0: 0 else: -1
  cp.renderTree()
  cp.h.flush()

# ----------------------------------------------------------------------------
# Open / close
# ----------------------------------------------------------------------------

proc open*(cp: CommandPalette) =
  if cp.isOpen: return
  cp.isOpen = true
  cp.opener = cp.h.focusedNode
  cp.query = ""
  if cp.h.root != nil:
    cp.h.renderer.appendChild(cp.h.root, cp.node)
  # Push a focus trap so Tab can't escape into background widgets.
  cp.h.focusManager.pushTrap(cp.node.id)
  cp.runQuery()
  discard cp.h.setFocus(cp.inputNode)

proc close*(cp: CommandPalette) =
  if not cp.isOpen: return
  cp.isOpen = false
  cp.h.focusManager.popTrap()
  if cp.h.root != nil and cp.node.parent != nil:
    cp.h.renderer.removeChild(cp.h.root, cp.node)
  if cp.opener != nil:
    discard cp.h.setFocus(cp.opener)
  else:
    cp.h.focusedId = 0
  if cp.onClose != nil: cp.onClose()
  cp.h.flush()

# ----------------------------------------------------------------------------
# Global keybinding (Ctrl+\)
# ----------------------------------------------------------------------------

proc isPaletteOpenKey*(ev: TerminalEvent): bool =
  ## Returns true when `ev` is the canonical "open palette" keystroke
  ## (Ctrl+`\`). Tests and the install helper share this predicate.
  if ev.kind != ekKey: return false
  if modCtrl notin ev.key.modifiers: return false
  let key = ev.key.key
  # The literal backslash key. Some drivers report it as `"\\"`,
  # others as `"backslash"` or `"\\u005c"`. Accept all reasonable
  # spellings.
  let lower = key.toLowerAscii
  return lower == "\\" or lower == "backslash" or
         (key.len == 1 and key[0] == '\\')

proc installGlobalBinding*(cp: CommandPalette; rootNode: TerminalNode = nil) =
  ## Wire the default `Ctrl+\` keybinding to `cp.open()`. The palette
  ## must respond to `Ctrl+\` no matter which widget currently has
  ## focus, so we install the keydown listener on the supplied root
  ## **and** every focusable descendant: in the test harness the
  ## pilot dispatches keydown to the focused node only, so a single
  ## root-level listener wouldn't fire when (e.g.) a `Button` is
  ## focused. Apps that prefer a different binding skip this and call
  ## `cp.open()` from their own handler.
  let root =
    if rootNode != nil: rootNode
    elif cp.h.root != nil: cp.h.root
    else: nil
  if root == nil: return
  let r = cp.h.renderer
  let handler = proc(ev: TerminalEvent) =
    if isPaletteOpenKey(ev) and not cp.isOpen:
      cp.open()
  r.addEventListener(root, "keydown", handler)
  proc walk(n: TerminalNode) =
    if n == nil: return
    if n != root:
      r.addEventListener(n, "keydown", handler)
    for c in n.children:
      walk(c)
  walk(root)

# ----------------------------------------------------------------------------
# Convenience: a default palette wired to a theme registry + a static
# app-command list. Mirrors Textual's `App.COMMANDS` plumbing.
# ----------------------------------------------------------------------------

proc newDefaultPalette*(h: TerminalTestHarness;
                       reg: ThemeRegistry = nil;
                       appCommands: openArray[tuple[text, help: string;
                                                    command: CommandCallback]] = [];
                       screens: openArray[tuple[name: string;
                                                activate: CommandCallback]] = []
                       ): CommandPalette =
  ## Convenience wrapper that registers the three built-in providers
  ## (app commands, screen switching, theme switching). Apps add more
  ## via `cp.registerProvider(...)`.
  var providers: seq[Provider] = @[]
  if appCommands.len > 0:
    providers.add newSimpleProvider("App commands", appCommands)
  if screens.len > 0:
    providers.add newSwitchScreenProvider(screens)
  if reg != nil:
    providers.add newSwitchThemeProvider(reg)
  newCommandPalette(h, providers)

# ----------------------------------------------------------------------------
# Introspection
# ----------------------------------------------------------------------------

proc topHit*(cp: CommandPalette): Hit =
  ## The current best hit, or a zero-score sentinel if there are none.
  if cp.hits.len == 0: return Hit(score: 0.0)
  cp.hits[0]

proc hitCount*(cp: CommandPalette): int {.inline.} = cp.hits.len

proc id*(cp: CommandPalette): int {.inline.} = cp.node.id
