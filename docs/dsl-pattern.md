# IsoNim-TUI DSL Pattern

This document describes the **canonical pattern** for composing
isonim-tui demos and ports using the IsoNim `ui()` DSL. It is the
template established by **DM-M0** (the task_app_demo pilot) and
applied across DM-M1 through DM-M6.

The `ui()` DSL itself lives in `isonim/src/isonim/dsl/ui.nim` (sibling
repo); this doc covers only how isonim-tui consumers should use it.

## TL;DR

Inside a `ui(r):` block, write structural divs as `tdiv(class="...")`
and mount M11+ widgets via the `w*` wrappers from
`isonim_tui/dsl/widget_blocks`:

```nim
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

result = ui(r):
  tdiv(class = "task-app-demo"):
    wHeader(r, "Tasks", "demo", cols)
    tdiv(class = "task-list"):
      for t in vm.tasks:
        tdiv:
          let mark = if t.completed: "[x] " else: "[ ] "
          wLabel(r, mark & t.name)
    wFooter(r, bindings, cols, true)
```

That is the worked example from `examples/task_app_demo/task_app_demo.nim`.

## What the DSL accepts

`isElementCall` (in `isonim/dsl/ui.nim`) classifies each call inside a
`ui()` body as one of three things:

1. **Known HTML tag** (`tdiv`, `span`, `button`, `tdiv(class="..."):
   ...`) — the macro emits `createElement` + `setAttribute` + child
   sub-tree.
2. **Bare positional call whose name is unknown** — treated as a
   node-returning Nim expression and appended via `appendChild`.
3. **Anything else** — passed through verbatim (the macro does
   `stmts.add(child)`), which is fine for `let`/`var`/`discard` but
   yields an unused-value compile error if the expression has a
   non-`void` type.

### Two acceptable forms

- **HTML tag** `tdiv(class = "...")` (or `span`, `button`, etc.) — for
  pure structural containers, divs, spans, headings. The DSL emits
  `createElement` + child sub-tree.
- **Positional widget call** `wHeader(r, ...)` from `widget_blocks` —
  for mounting M11+ widgets (Static, Label, Button, Header, Footer,
  ...). The DSL treats it as a bare call returning a `TerminalNode`
  and appends it to the parent.

### Form to avoid inside `ui()` blocks

Inside `ui()`, **do not** use:

- `newButton(r, "x").node` — `nnkDotExpr`, not a call. The DSL passes
  it through verbatim and the compiler rejects the unused
  `TerminalNode`.
- Calls with **named arguments**, e.g. `wHeader(r, title="x")`. Per
  `isElementCall`, *any* `nnkExprEqExpr` argument promotes the call
  to an HTML element. The macro then emits `setAttribute("title",
  "x")` on a synthetic element instead of forwarding to your widget.
  Worse, `width = cols` matches the CSS `styleProperties` list and
  triggers `setStyle`-with-`createRenderEffect` emission, which
  fails to compile against `TerminalRenderer`.

These two restrictions are why `widget_blocks.nim` exists: each
wrapper takes positional args and returns a `TerminalNode` directly.
The wrappers are deliberately **thin** — they forward to
`newWidget(...)` with named arguments internally (so reading the
wrapper signature shows you the widget's actual configuration
surface). You only call them with positional args at the
`ui(r):`-block call site.

## Naming convention

- Wrapper procs are prefixed with **`w`** followed by the widget's
  natural name: `wHeader`, `wFooter`, `wLabel`, `wButton`, etc.
- One wrapper per widget constructor, defined in
  `src/isonim_tui/dsl/widget_blocks.nim`.
- The wrapper's parameter list mirrors the underlying constructor's
  parameter order so the full widget configuration surface is
  reachable.
- Wrappers always return `TerminalNode` (the widget's `.node`
  field).

When you need the widget object (e.g. to mutate state or wire up a
ref), call the underlying `newWidget(...)` constructor outside the
`ui()` block and reference the resulting node either via `ref =
varName` (DSL form) or by appending to a captured parent.

## Worked example: task_app_demo

Before (imperative):

```nim
let r = h.renderer
let root = r.createElement("div")
r.setAttribute(root, "class", "task-app-demo")

let header = newHeader(r, title = "Tasks", subtitle = "demo",
                       width = h.cols)
r.appendChild(root, header.node)

let listBox = r.createElement("div")
r.setAttribute(listBox, "class", "task-list")
if vm.tasks.len == 0:
  r.appendChild(listBox, r.createTextNode("(no tasks yet)"))
else:
  for t in vm.tasks:
    let row = r.createElement("div")
    let mark = if t.completed: "[x] " else: "[ ] "
    let lbl = newLabel(r, mark & t.name)
    r.appendChild(row, lbl.node)
    r.appendChild(listBox, row)
r.appendChild(root, listBox)

let footer = newFooter(r, bindings = ..., width = h.cols, compact = true)
r.appendChild(root, footer.node)
root
```

After (DSL):

```nim
let r = h.renderer
let cols = h.cols
let footerBindings = @[
  FooterBinding(key: "n", description: "New task"),
  FooterBinding(key: "x", description: "Toggle done"),
  FooterBinding(key: "q", description: "Quit")]

result = ui(r):
  tdiv(class = "task-app-demo"):
    wHeader(r, "Tasks", "demo", cols)
    tdiv(class = "task-list"):
      if vm.tasks.len == 0:
        text "(no tasks yet)"
      else:
        for t in vm.tasks:
          tdiv:
            let mark = if t.completed: "[x] " else: "[ ] "
            wLabel(r, mark & t.name)
    wFooter(r, footerBindings, cols, true)
```

The `if`/`else` and `for` are recognised by the DSL macro and rewrite
their bodies as DSL children, so control flow works identically to a
plain Nim block.

## Goldens

The DSL refactor of `task_app_demo` produces a **byte-identical**
tree to the imperative original. The treedump, plaintext, ANSI, SVG,
annotated SVG, and cellmap snapshots are all unchanged — no
re-recording was needed in DM-M0. This is the expected outcome for
demos that simply translate one composition style into another.

If a future demo's DSL refactor produces a different tree shape
(e.g. an extra wrapper div inserted by the DSL's multi-root fragment
behaviour, or a different child order under control flow), the
authoring agent must (a) re-record goldens, (b) document the diff in
this file under a new "Known DSL tree-shape differences" section,
and (c) reference the milestone where the divergence first appears.

## DSL gaps discovered in DM-M0

Two gaps surfaced during the pilot. Both are documented above and
mitigated by the wrapper convention; neither is fixed in DM-M0
(out-of-scope per the milestone brief).

1. **Named arguments promote a call to an HTML element.**
   `isElementCall` returns `true` for any call containing
   `nnkExprEqExpr`. A widget wrapper called with `width = cols`
   triggers `setStyle("width", cols)` emission (because `width` is in
   `styleProperties`) wrapped in `createRenderEffect`, which fails to
   resolve. *Mitigation:* wrappers must be called with positional
   args inside `ui()` blocks.

2. **`.node` is a `nnkDotExpr`, not a call.** The DSL does not
   recognise it as a child to append. *Mitigation:* never use
   `.node` inside a `ui()` body — use a wrapper that returns the
   node directly.

Both could be addressed by extending the `ui()` macro itself
(e.g. detect dot-suffixed calls, or add an explicit "this is a
node, append it" syntax). Such changes are deferred to a future
milestone in `isonim/`.

## Cross-link to M22 / DM-M6

DM-M6 will refactor `examples/task_app/` (the canonical M22
cross-platform reference) to use this same pattern. Until that
milestone lands, the M22 task app retains the imperative widget
constructor pattern from M11/M12. The naming convention here
(`wWidget` returning `TerminalNode`) was chosen so the M22
refactor can reuse `widget_blocks.nim` directly without renames.
