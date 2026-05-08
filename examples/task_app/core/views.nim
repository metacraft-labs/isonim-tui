## examples/task_app/core/views.nim — Layer-2 high-level view.
##
## Renderer-agnostic composition layer. Calls Layer-1 leaves
## (`appShell`, `taskInput`, `filterBar`, `taskList`, `summaryBar`) by
## name. Each platform's `leaves.nim` provides those procs against its
## own renderer type, so this file compiles against either the
## TerminalRenderer (TUI) or the MockRenderer / WebRenderer (web)
## without modification.
##
## Pattern: this file is *included* (not imported) by the composition
## roots. The composition root imports the platform leaves first, then
## includes this file — name resolution picks up the platform-specific
## leaves. This keeps `views.nim` byte-identical across all targets.
##
## Cross-platform architecture:
## `codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`
## §"Layer 2 — High-level view".

# Note: imports for `vm` (TaskAppVM, FilterMode) and the renderer/leaves
# modules are made by the composition root before this file is included.
# Adding `import` statements here would shadow that arrangement.

template renderTaskApp*(renderer, viewModel): untyped {.dirty.} =
  ## Build the full task-app tree against the given renderer. Returns
  ## the root element. The root and child element types are inferred
  ## from the leaf procs in the calling scope, which makes this
  ## template equally valid against `TerminalRenderer`/`TerminalNode`
  ## and `MockRenderer`/`MockNode`.
  ##
  ## The shape mirrors the spec example in
  ## `isonim-cross-platform-architecture.md` §"Worked example":
  ##   appShell
  ##     taskInput      — single-line text + Enter to submit
  ##     filterBar      — All / Active / Completed
  ##     taskList       — visible tasks per current filter
  ##     summaryBar     — count of remaining tasks
  ##
  ## Every leaf is a Layer-1 platform component; this template never
  ## touches the renderer's mutators directly.
  block:
    let appRoot = appShell(renderer, viewModel)
    let inputNode = taskInput(renderer, viewModel)
    renderer.appendChild(appRoot, inputNode)
    let filterNode = filterBar(renderer, viewModel)
    renderer.appendChild(appRoot, filterNode)
    let listNode = taskList(renderer, viewModel)
    renderer.appendChild(appRoot, listNode)
    let summaryNode = summaryBar(renderer, viewModel)
    renderer.appendChild(appRoot, summaryNode)
    appRoot
