## isonim_tui/reactive_root.nim — NH-M1 reactive root entry point for the TUI.
##
## `renderTui` is the TUI's half of the native mount seam described in
## `isonim-specs/Hot-Module-Reload-Native.milestones.org`
## (NH-M1). It routes the root build through `isonim/renderers/native`'s
## `renderNative`, which opens a `createRoot` scope and re-runs the accessor
## inside a `createRenderEffect`.
##
## Why the seam has to exist before NH-M2 can be written: the hot-component
## proxy swaps the ROOT component. Without a render effect at the insertion
## site, the only way to install a different root is to dispose the reactive
## root and mount again — which drops every signal, resource and cleanup the
## running app owns, i.e. exactly the state HMR exists to preserve. With the
## seam, the proxy writes a signal the accessor reads and the mount re-runs
## inside the *same* root.
##
## This module deliberately does NOT import the `isonim_tui` aggregate module:
## that module pulls in `isonim_tui/syntax/treesitter_ffi`, which links the
## tree-sitter grammar archive. Importing `isonim_tui/reactive_root` directly
## keeps the reactive seam (and its tests) free of that link-time dependency.

import ./renderer
import ./testing/harness

import isonim/renderers/native as native_root
export native_root.NativeRootAccessor, native_root.NativeRootMount,
       native_root.NativeRootHandle, native_root.renderNative,
       native_root.staticNativeRoot, native_root.dispose,
       native_root.isDisposed

proc renderTui*(h: TerminalTestHarness;
                accessor: NativeRootAccessor[TerminalNode]
               ): NativeRootHandle[TerminalNode] =
  ## Mount `accessor`'s tree into `h` through a reactive root.
  ##
  ## The mount step is `mountTree` + the harness's own synchronous `flush`
  ## contract, so every run of the render effect ends with a repainted screen
  ## buffer. It runs on EVERY effect run, not only when the root node changes
  ## identity: a signal write that mutates the existing tree in place still has
  ## to reach the compositor.
  renderNative(accessor, proc(node: TerminalNode) =
    h.mountTree(node))

proc renderTui*(h: TerminalTestHarness;
                build: proc(r: TerminalRenderer): TerminalNode
               ): NativeRootHandle[TerminalNode] =
  ## Convenience overload mirroring `TerminalTestHarness.mount`: the build proc
  ## receives the harness's renderer.
  ##
  ## Tracking is ON, exactly as for the accessor overload — wrap `build` in
  ## `staticNativeRoot` at the call site to get build-once semantics.
  if build == nil:
    raise newException(ValueError,
      "renderTui: build proc is nil — there is no root to construct")
  let r = h.renderer
  renderTui(h, proc(): TerminalNode = build(r))
