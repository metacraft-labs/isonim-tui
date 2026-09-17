## NH-M1 verification: test_render_native_tui_reactive
##
## Claim under test (from
## `codetracer-specs/Front-Ends/IsoNim/Hot-Module-Reload-Native.milestones.org`,
## NH-M1): "`renderTui` wraps the root in a render-effect; mutating a signal in
## the root proc fires the effect and produces a new screen buffer."
##
## MOCK POLICY: no mocks. `TerminalTestHarness` is isonim-tui's real headless
## stack — real `TerminalRenderer`, real compositor, real `HeadlessDriver`,
## real `ScreenBuffer`. The reactive core (`createSignal`, `createRoot`,
## `createRenderEffect`) is the real one from `isonim/core`. The assertions
## below read the PAINTED CELL GRID via `encodePlaintext(h.screenBuffer())`,
## not the element tree, so "a new screen buffer" is measured rather than
## inferred from the fact that a callback ran.
##
## NO SKIP ARMS. This suite has no prerequisite probe and no early return:
## the headless driver needs neither a TTY nor a display, so there is nothing
## legitimate to skip on. If it cannot run, it must go red.
##
## DISCRIMINATION. Each reactive case is paired with a control that mounts the
## same tree through the pre-NH-M1 imperative path (`h.mount`) or through
## `staticNativeRoot` (the untracked accessor non-HMR callers use), and
## asserts the screen does NOT change on the same signal write. Measured: with
## the `createRenderEffect` removed from `renderNative`, the reactive cases go
## red and both controls stay green (see the NH-M1 verification log).

import std/strutils
import unittest

import isonim_tui/renderer
import isonim_tui/testing/harness
import isonim_tui/testing/snapshot/plaintext as snapPlain
import isonim_tui/reactive_root

import isonim/core/signals

proc buildLabelRoot(r: TerminalRenderer; text: string): TerminalNode =
  ## A fresh root every call. `renderNative`'s reactive insert is what has to
  ## notice the new root and get it onto the surface.
  let root = r.createElement("div")
  let line = r.createElement("span")
  r.appendChild(line, r.createTextNode(text))
  r.appendChild(root, line)
  root

proc screenText(h: TerminalTestHarness): string =
  snapPlain.encodePlaintext(h.screenBuffer())

suite "NH-M1: renderTui reactive root (isonim-tui)":

  test "test_render_native_tui_reactive":
    let h = newTerminalTestHarness(40, 6)
    let label = createSignal("ALPHA")

    let handle = renderTui(h, proc(r: TerminalRenderer): TerminalNode =
      buildLabelRoot(r, label.val))

    # Mounted, painted, and the reactive root is live.
    check handle.renders == 1
    check handle.rootSwaps == 1
    check not isDisposed(handle)
    let firstFrame = screenText(h)
    check contains(firstFrame, "ALPHA")
    check not contains(firstFrame, "BETA")

    # The claim: a signal write inside the root proc fires the effect …
    label.val = "BETA"

    check handle.renders == 2
    check handle.rootSwaps == 2
    # … and produces a NEW screen buffer.
    let secondFrame = screenText(h)
    check secondFrame != firstFrame
    check contains(secondFrame, "BETA")
    check not contains(secondFrame, "ALPHA")

    # A third write keeps going — the seam is not a one-shot.
    label.val = "GAMMA"
    check handle.renders == 3
    let thirdFrame = screenText(h)
    check contains(thirdFrame, "GAMMA")
    check not contains(thirdFrame, "BETA")

    handle.dispose()
    h.dispose()

  test "test_control_tui_imperative_mount_does_not_repaint_on_signal_write":
    # DISCRIMINATION CONTROL. Identical tree, identical signal, mounted the
    # pre-NH-M1 way (`TerminalTestHarness.mount`). If the screen changed here
    # too, the case above would be measuring something ambient rather than
    # the render effect.
    let h = newTerminalTestHarness(40, 6)
    let label = createSignal("ALPHA")

    h.mount(proc(r: TerminalRenderer): TerminalNode =
      buildLabelRoot(r, label.val))
    let firstFrame = screenText(h)
    check contains(firstFrame, "ALPHA")

    label.val = "BETA"

    let secondFrame = screenText(h)
    check secondFrame == firstFrame
    check contains(secondFrame, "ALPHA")
    check not contains(secondFrame, "BETA")
    h.dispose()

  test "test_control_tui_static_native_root_keeps_build_once_semantics":
    # The "no behaviour change for non-HMR callers" deliverable, measured:
    # the seam is present but the accessor is untracked, exactly as web
    # `render()` untracks its root build. Observable behaviour must match the
    # imperative control above.
    let h = newTerminalTestHarness(40, 6)
    let label = createSignal("ALPHA")
    let renderer = h.renderer

    let handle = renderTui(h, staticNativeRoot(proc(): TerminalNode =
      buildLabelRoot(renderer, label.val)))
    check handle.renders == 1
    let firstFrame = screenText(h)
    check contains(firstFrame, "ALPHA")

    label.val = "BETA"

    check handle.renders == 1
    let secondFrame = screenText(h)
    check secondFrame == firstFrame
    check not contains(secondFrame, "BETA")

    handle.dispose()
    h.dispose()

  test "test_render_native_tui_root_swap_replaces_the_surface_not_appends":
    # The NH-M2 shape, minus NH-M2: an accessor that returns a DIFFERENT root
    # tree on a signal write — which is what a hot-component proxy does. The
    # harness must end up holding exactly the new root, with the old one gone
    # from the painted buffer.
    let h = newTerminalTestHarness(40, 6)
    let variant = createSignal(0)
    let renderer = h.renderer

    let rootA = buildLabelRoot(renderer, "ROOT-A")
    let rootB = buildLabelRoot(renderer, "ROOT-B")

    let handle = renderTui(h, NativeRootAccessor[TerminalNode](proc(): TerminalNode =
      if variant.val == 0: rootA else: rootB))

    check h.root == rootA
    check contains(screenText(h), "ROOT-A")

    variant.val = 1

    check handle.renders == 2
    check handle.rootSwaps == 2
    check h.root == rootB
    let frame = screenText(h)
    check contains(frame, "ROOT-B")
    check not contains(frame, "ROOT-A")

    handle.dispose()
    h.dispose()

  test "test_render_native_tui_dispose_stops_repainting":
    let h = newTerminalTestHarness(40, 6)
    let label = createSignal("ALPHA")

    let handle = renderTui(h, proc(r: TerminalRenderer): TerminalNode =
      buildLabelRoot(r, label.val))
    label.val = "BETA"
    check handle.renders == 2
    let afterWrite = screenText(h)

    handle.dispose()
    label.val = "GAMMA"

    check handle.renders == 2
    check screenText(h) == afterWrite
    check not contains(screenText(h), "GAMMA")
    h.dispose()

  test "test_render_native_tui_rejects_a_nil_build_proc":
    # Loud prerequisite rather than a silently empty mount.
    let h = newTerminalTestHarness(40, 6)
    let nilBuild: proc(r: TerminalRenderer): TerminalNode = nil
    expect ValueError:
      discard renderTui(h, nilBuild)
    let nilAccessor: NativeRootAccessor[TerminalNode] = nil
    expect ValueError:
      discard renderTui(h, nilAccessor)
    h.dispose()
