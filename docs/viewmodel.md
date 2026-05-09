# ViewModel Pattern

`isonim-tui` reuses the **IsoNim cross-platform architecture** rather
than reinventing one. A typical TUI app has four layers:

1. **Layer 4 — composition root.** Wires the VM, the leaves, and the
   harness/driver together. One file per platform target. (`main_tui.nim`,
   `main_web.nim`, etc.)
2. **Layer 3 — ViewModel (pure logic).** Renderer-agnostic state,
   actions, and derived views. **Byte-identical across every platform**
   (web, terminal, Cocoa, GPUI). Imports nothing from the renderer or
   widgets — only `isonim/core/signals`.
3. **Layer 2 — views.** Build the platform-agnostic node tree from the
   VM. The `views` module names the leaves it expects to find at
   Layer 1.
4. **Layer 1 — leaves.** Per-platform widget instantiation. Wires VM
   actions to widget event listeners; rebuilds affected sub-trees on
   VM mutations.

The canonical worked example lives at
`examples/task_app/`. Its `core/vm.nim` is shared verbatim with the web
target; `tui/leaves.nim` consumes the M11–M21 widgets; `core/views.nim`
is the cross-platform glue.

## Cross-link to the IsoNim docs

The same ViewModel pattern is documented in detail in the IsoNim repo.
Open the file directly for the full discussion (Karax DSL, reactive
signals, GUI-agnostic core, and the SSR story):

- `metacraft/isonim/docs/` (absolute path; relative cross-repo links
  do not resolve in standard Markdown viewers).

The cross-platform architecture spec lives in:

- `metacraft/codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`

## Reactive primitives

Layer 3 imports `isonim/core/signals` and uses three primitives:

- `Signal[T]` — a mutable cell with subscribers; reads register
  dependencies inside an effect.
- `createSignal[T](init)` — construct one.
- `createRenderEffect(proc())` — declare a reactive effect (used at
  Layer 1 to bind widget state to signals).

The task app's VM stores three signals:

```nim
type TaskAppVM* = ref object
  tasks*: Signal[seq[Task]]
  filter*: Signal[FilterMode]
  inputText*: Signal[string]
  nextId: int
```

Actions mutate these signals:

```nim
proc addTask*(vm: TaskAppVM; name: string) =
  var ts = vm.tasks.val
  ts.add Task(id: vm.nextId, name: name, completed: false)
  inc vm.nextId
  vm.tasks.val = ts          # Notifies subscribers.
```

Layer 1 leaves react via either a `createRenderEffect` (full reactive
binding) or — for small apps — a manual `rerender(vm)` after every
mutation. The task app picks the manual path because the surface is
small enough that explicit re-renders read more clearly.

## When NOT to split the layers

For demos that target a single platform and won't grow, you can
collapse Layer 1+2+3 into a single file. The split pays off when:

- You'll ship the same logic to web and TUI (or any other IsoNim
  target).
- The VM's state needs unit tests independent of the renderer.
- A debugger consumes the VM (M25 recordings replay against the VM,
  not the rendered tree).

## Headless tests against the VM

Every Layer-3 VM is testable without a renderer. The task app's
`VMSnapshot` is a plain value object — assert on it directly:

```nim
let vm = newTaskAppVM()
vm.addTask("Buy milk")
vm.addTask("Write specs")
let snap = vm.snapshot()
check snap.tasks.len == 2
```

The web target re-uses this exact assertion pattern, which is how the
M22 test_task_app_shared_vm_byte_identical guarantee survives across
platforms.
