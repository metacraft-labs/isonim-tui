## test_palette_open_search_run — M16 mandatory test.
##
## Real-stack integration of the M16 command palette: install the
## `Ctrl+\` keybinding, press it, type "th", and verify that
## `Switch theme: textual-light` (or whichever theme tops the list)
## floats to the top of the hits, that pressing `Enter` runs its
## callback, that the active theme actually changes, and that the
## palette dismisses with focus restored to the previously-focused
## widget.
##
## Charter: no mocks. The fuzzy matcher, the `ThemeRegistry`, the
## focus manager, the modal layering, and the harness's input pipeline
## all exercise real code.

import unittest
import std/strutils
import isonim_tui

suite "M16: command palette":
  test "test_palette_open_search_run":
    let h = newTerminalTestHarness(60, 16)
    var opener: ButtonWidget
    var palette: CommandPalette
    let reg = newThemeRegistry()

    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      opener = newButton(r, "Click Me", width = 10)
      r.appendChild(root, opener.node)
      # Build a default palette wired to the theme registry. Add an
      # extra app-command entry so the search corpus has at least one
      # non-theme candidate.
      palette = newDefaultPalette(h, reg, appCommands = [
        (text: "Save File", help: "Save current document",
         command: proc() {.closure.} = discard),
        (text: "Quit", help: "Exit application",
         command: proc() {.closure.} = discard),
      ])
      palette.installGlobalBinding(root)
      root)

    let p = newPilot(h)
    p.focus(opener.node)
    check h.focusedNode != nil
    check h.focusedNode.id == opener.node.id

    # Active theme starts as textual-dark.
    check reg.activeName == "textual-dark"
    check (not palette.isOpen)

    # --- Open via Ctrl+\ ---
    p.press("ctrl+\\")
    check palette.isOpen
    # Focus moves into the palette input.
    check h.focusedNode != nil
    check h.focusedNode.id == palette.inputNode.id

    # --- Type "th" — the theme-switching hits should float to the top
    p.typeText("th")
    check palette.query == "th"
    check palette.hitCount > 0
    let topHit = palette.topHit
    # The top hit should be one of the theme switches (the theme
    # provider's commands all start with "Switch theme: …" → the
    # fuzzy matcher gives them a high score for "th").
    check topHit.text.startsWith("Switch theme:")
    check topHit.score > 0.0

    # --- Move selection to a *non-current* theme. Default selection
    # is index 0 which may be "textual-dark" (the active one) or
    # another theme depending on alphabetical order from the
    # ThemeRegistry. Find the first non-active hit and select it.
    var targetIdx = -1
    for i in 0 ..< palette.hits.len:
      let nm = palette.hits[i].text
      if nm.startsWith("Switch theme:") and not nm.endsWith("textual-dark"):
        targetIdx = i
        break
    check targetIdx >= 0
    while palette.selectedIdx < targetIdx:
      p.press("down")
    check palette.selectedIdx == targetIdx

    let chosenName = palette.hits[targetIdx].text
    # Chosen name is "Switch theme: <name>".
    let parts = chosenName.split(": ", 1)
    check parts.len == 2
    let newThemeName = parts[1]
    check newThemeName != "textual-dark"

    # --- Enter runs the command and closes the palette ---
    p.press("enter")
    check (not palette.isOpen)
    check reg.activeName == newThemeName

    # --- Focus returns to the opener ---
    check h.focusedNode != nil
    check h.focusedNode.id == opener.node.id

    h.dispose()

  test "palette_escape_closes_without_running":
    let h = newTerminalTestHarness(60, 16)
    var opener: ButtonWidget
    var palette: CommandPalette
    var ranCount = 0

    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      opener = newButton(r, "Anchor", width = 10)
      r.appendChild(root, opener.node)
      let provider = newSimpleProvider("Test", [
        (text: "Run me",
         help: "",
         command: proc() {.closure.} = inc ranCount),
      ])
      palette = newCommandPalette(h, [provider])
      palette.installGlobalBinding(root)
      root)

    let p = newPilot(h)
    p.focus(opener.node)
    p.press("ctrl+\\")
    check palette.isOpen
    p.typeText("run")
    check palette.hitCount == 1
    p.press("escape")
    check (not palette.isOpen)
    check ranCount == 0
    check h.focusedNode.id == opener.node.id
    h.dispose()

  test "palette_user_provider_closure":
    let h = newTerminalTestHarness(60, 12)
    var palette: CommandPalette
    var lastInvoked = ""

    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let prov = newUserProvider("Custom",
        searchProc = proc(query: string): seq[Hit] =
          if query.len == 0: return @[]
          var hits: seq[Hit] = @[]
          for label in ["Alpha", "Beta", "Gamma"]:
            let s = fuzzyScore(query, label)
            if s > 0:
              let lbl = label
              hits.add newHit(s, label,
                              proc() {.closure.} = lastInvoked = lbl,
                              text = label)
          hits)
      palette = newCommandPalette(h, [prov])
      palette.installGlobalBinding(root)
      root)

    let p = newPilot(h)
    p.press("ctrl+\\")
    check palette.isOpen
    p.typeText("alp")
    check palette.hitCount == 1
    check palette.topHit.text == "Alpha"
    p.press("enter")
    check (not palette.isOpen)
    check lastInvoked == "Alpha"
    h.dispose()

  test "palette_arrow_navigation_wraps":
    let h = newTerminalTestHarness(60, 12)
    var palette: CommandPalette
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let prov = newSimpleProvider("Many", [
        (text: "alpha", help: "", command: proc() {.closure.} = discard),
        (text: "alphabet", help: "", command: proc() {.closure.} = discard),
        (text: "alphanumeric", help: "", command: proc() {.closure.} = discard),
      ])
      palette = newCommandPalette(h, [prov])
      palette.installGlobalBinding(root)
      root)
    let p = newPilot(h)
    p.press("ctrl+\\")
    p.typeText("alp")
    check palette.hitCount == 3
    check palette.selectedIdx == 0
    p.press("down")
    check palette.selectedIdx == 1
    p.press("down")
    check palette.selectedIdx == 2
    p.press("down")  # wrap
    check palette.selectedIdx == 0
    p.press("up")  # wrap up
    check palette.selectedIdx == 2
    p.press("escape")
    h.dispose()

  test "palette_backspace_shortens_query":
    let h = newTerminalTestHarness(60, 12)
    var palette: CommandPalette
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      palette = newDefaultPalette(h, appCommands = [
        (text: "thunderstorm", help: "",
         command: proc() {.closure.} = discard)])
      palette.installGlobalBinding(root)
      root)
    let p = newPilot(h)
    p.press("ctrl+\\")
    p.typeText("thu")
    check palette.query == "thu"
    p.press("backspace")
    check palette.query == "th"
    p.press("backspace")
    check palette.query == "t"
    p.press("escape")
    h.dispose()

  test "palette_provider_kinds_compose":
    ## Simple + theme + screen providers all coexist in one palette;
    ## queries route through every provider's search proc.
    let h = newTerminalTestHarness(60, 14)
    var palette: CommandPalette
    let reg = newThemeRegistry()
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      palette = newDefaultPalette(h, reg, appCommands = [
        (text: "Reload", help: "Reload window",
         command: proc() {.closure.} = discard),
      ], screens = [
        (name: "Editor", activate: proc() {.closure.} = discard),
        (name: "Settings", activate: proc() {.closure.} = discard),
      ])
      palette.installGlobalBinding(root)
      root)
    let p = newPilot(h)
    p.press("ctrl+\\")
    check palette.providers.len == 3
    p.typeText("se")  # 'se' should match Settings + several themes
    check palette.hitCount > 0
    p.press("escape")
    h.dispose()
