## test_renderer_concept_conformance
##
## Verifies M0's headline guarantee: every renderer in the family
## (MockRenderer from isonim, the renamed demo TerminalRenderer in
## isonim, and `isonim_tui.TerminalRenderer`) satisfies
## `checkRendererBackend[B, E]()`, and the same renderer-agnostic
## counter component compiles against all three.
##
## "No mocks" caveat: MockRenderer is part of isonim's testing surface,
## not a mock for *isonim_tui*. We exercise it here only to prove the
## conformance check works uniformly across the renderer family.

import unittest
import std/[strutils, tables]

# All three renderers + the abstract concept.
import isonim/renderers/abstract_renderer
import isonim/testing/mock_dom
import isonim/renderers/terminal_demo as demo_term
import isonim_tui/renderer as tui_renderer
import isonim_tui/events

import isonim/core/[signals, computation, owner]

# Re-exported by isonim_tui.renderer:
type TuiRenderer = tui_renderer.TerminalRenderer
type TuiNode = tui_renderer.TerminalNode

# ---- The three compile-time conformance proofs ----
#
# `checkRendererBackend` is a `compileTime` proc whose body invokes
# `createElement` (which mutates the per-thread id counter — not
# permitted inside a `static:` block on the Nim VM). Following the
# pattern from `isonim/src/isonim/renderers/terminal.nim` we use
# `when not compiles(...)` instead, which performs the type-checking
# without actually executing the body. If any required proc is missing
# or has the wrong signature on any of the three backends, this file
# fails to compile with a precise error.

when not compiles(checkRendererBackend[MockRenderer, MockNode]()):
  {.error: "MockRenderer no longer satisfies RendererBackend".}
when not compiles(checkRendererBackend[demo_term.TerminalRenderer, demo_term.TerminalNode]()):
  {.error: "demo TerminalRenderer no longer satisfies RendererBackend".}
when not compiles(checkRendererBackend[TuiRenderer, TuiNode]()):
  {.error: "isonim_tui.TerminalRenderer no longer satisfies RendererBackend".}

# ---- Renderer-agnostic counter component ----
# Same shape as the one in `isonim/tests/test_terminal.nim`. Generic
# over `R` and `N` so it works against any RendererBackend.

proc createCounter[R, N](renderer: R): N =
  let count = createSignal(0)
  let container = renderer.createElement("div")
  let label = renderer.createTextNode("")
  let incBtn = renderer.createElement("button")
  let decBtn = renderer.createElement("button")
  renderer.appendChild(incBtn, renderer.createTextNode("+"))
  renderer.appendChild(decBtn, renderer.createTextNode("-"))
  renderer.appendChild(container, label)
  renderer.appendChild(container, incBtn)
  renderer.appendChild(container, decBtn)
  renderer.addEventListener(incBtn, "click", proc() = count.val = count.val + 1)
  renderer.addEventListener(decBtn, "click", proc() = count.val = count.val - 1)
  createRenderEffect do:
    renderer.setTextContent(label, "Count: " & $count.val)
  return container

# ---- Real-stack tests ----

suite "Renderer concept conformance":
  test "test_compile_time_conformance":
    ## If this test compiles, the `static:` block above already proved
    ## the concept; we just check we can still construct each renderer
    ## at runtime.
    let mockR = MockRenderer()
    let demoR = demo_term.TerminalRenderer()
    let tuiR = tui_renderer.TerminalRenderer()
    discard mockR.createElement("div")
    discard demoR.createElement("div")
    discard tuiR.createElement("div")
    check true

  test "test_counter_compiles_against_all_three_renderers":
    ## The same `createCounter` body type-checks against every
    ## renderer — proves the renderer-agnostic component pattern is
    ## load-bearing for the demo→production migration.
    createRoot do (dispose: proc()):
      mock_dom.nextMockNodeId = 0
      tui_renderer.resetNodeIds()
      demo_term.nextTerminalNodeId = 0

      let mockApp = createCounter[MockRenderer, MockNode](MockRenderer())
      let demoApp = createCounter[demo_term.TerminalRenderer, demo_term.TerminalNode](
                      demo_term.TerminalRenderer())
      let tuiApp = createCounter[TuiRenderer, TuiNode](tui_renderer.TerminalRenderer())

      # Same tree shape: container → [label, incBtn, decBtn].
      check mockApp.children.len == 3
      check demoApp.children.len == 3
      check tuiApp.children.len == 3

      # All three labels start at "Count: 0".
      check mock_dom.textContent(mockApp.children[0]) == "Count: 0"
      check demo_term.textContent(demoApp.children[0]) == "Count: 0"
      check tui_renderer.textContent(tuiApp.children[0]) == "Count: 0"

      # Drive the tui app: increment twice, decrement once → 1.
      let tuiInc = tuiApp.children[1]
      let tuiDec = tuiApp.children[2]
      tui_renderer.fireEvent(tuiInc, "click")
      tui_renderer.fireEvent(tuiInc, "click")
      tui_renderer.fireEvent(tuiDec, "click")
      check tui_renderer.textContent(tuiApp.children[0]) == "Count: 1"

      dispose()

  test "test_tui_renderer_basic_ops":
    ## Sanity-check every individual proc on the new renderer.
    tui_renderer.resetNodeIds()
    let r = tui_renderer.TerminalRenderer()
    let div1 = r.createElement("div")
    check div1.tag == "div"
    check div1.kind == tnkBox
    check div1.id == 1

    let txt = r.createTextNode("hi")
    check txt.kind == tnkText
    check txt.text == "hi"
    check txt.id == 2

    r.appendChild(div1, txt)
    check div1.children.len == 1
    check r.firstChild(div1) == txt
    check r.parentNode(txt) == div1

    let btn = r.createElement("button")
    r.appendChild(div1, btn)
    check r.nextSibling(txt) == btn

    r.setAttribute(div1, "class", "main")
    check div1.attributes["class"] == "main"
    r.removeAttribute(div1, "class")
    check "class" notin div1.attributes

    r.setStyle(div1, "color", "red")
    check div1.styles["color"] == "red"

    r.setTextContent(txt, "world")
    check txt.text == "world"

    var clicked = false
    r.addEventListener(btn, "click", proc() = clicked = true)
    btn.fireEvent("click")
    check clicked

    r.removeChild(div1, txt)
    check div1.children.len == 1
    check r.firstChild(div1) == btn

    let newTxt = r.createTextNode("before")
    r.insertBefore(div1, newTxt, btn)
    check div1.children.len == 2
    check r.firstChild(div1) == newTxt

    # clearChildren / clearEventListeners (the two extras beyond the
    # core 13 — they're not in the concept check but are part of the
    # full renderer surface).
    r.clearChildren(div1)
    check div1.children.len == 0
    r.clearEventListeners(btn)
    check btn.eventListeners.len == 0
    check btn.eventHandlers.len == 0

  test "test_event_arg_handler_overload":
    ## The (ev: TerminalEvent) overload mirrors mock_dom.nim:124 and
    ## web_renderer.nim:93 — same pattern; the DSL picks this overload
    ## when the user writes `(ev) => ev.preventDefault()`.
    tui_renderer.resetNodeIds()
    let r = tui_renderer.TerminalRenderer()
    let btn = r.createElement("button")
    var seenType = ""
    var seenTarget = 0
    r.addEventListener(btn, "click", proc(ev: events.TerminalEvent) =
      seenType = ev.`type`
      seenTarget = ev.targetId)
    btn.fireEvent("click")
    check seenType == "click"
    check seenTarget == btn.id

  test "test_tree_shape_parity":
    ## Mock and tui produce identical tree-shape JSON-ish dumps for
    ## the same component. Captures structural parity in one place.
    proc dump[N](root: N; depth: int = 0): string =
      let indent = "  ".repeat(depth)
      result = indent & "<" & root.tag & ">" & "\n"
      for c in root.children:
        result.add dump(c, depth + 1)

    createRoot do (dispose: proc()):
      mock_dom.nextMockNodeId = 0
      tui_renderer.resetNodeIds()
      let mockApp = createCounter[MockRenderer, MockNode](MockRenderer())
      let tuiApp = createCounter[TuiRenderer, TuiNode](tui_renderer.TerminalRenderer())
      check dump(mockApp) == dump(tuiApp)
      dispose()
