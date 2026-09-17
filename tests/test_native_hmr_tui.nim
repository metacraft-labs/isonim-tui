## NH-M2 end-to-end against a real renderer.
##
## Claim under test (NH-M2 deliverable 6): "At least one renderer (TUI is
## the cheapest) demonstrating end-to-end: mount with ``mountUiHot``,
## drive a simulated reload, observe the screen buffer change without
## re-running the mount."
##
## MOCK POLICY. Exactly one double: ``isonim/tests/helpers/hcr_stub.nim``,
## the Reprobuild HCR agent, justified in full in that file — the shipped
## ``librepro_hcr_agent`` exports the ten ``rb_hcr_*`` symbols with
## baseline bodies that never fire a callback, and live dispatch is
## Reprobuild HLX-M8, which is ``planned``, so the real library would
## exercise the reload lifecycle zero times.
##
## Nothing else is faked. ``TerminalTestHarness`` is isonim-tui's real
## headless stack (real ``TerminalRenderer``, real compositor, real
## ``HeadlessDriver``, real ``ScreenBuffer``); the registry, the slot
## memos and the reactive core are the production objects. The
## assertions read the PAINTED CELL GRID through
## ``encodePlaintext(h.screenBuffer())``, so "the screen buffer changed"
## is measured on the surface rather than inferred from a callback
## having run.
##
## NO SKIP ARMS. The headless driver needs neither a TTY nor a display,
## so there is nothing legitimate to skip on.
##
## THE OPERATIVE ASSERTION is not "the text changed" — it is that the
## text changed while ``uiHotMounts`` (a process-wide count of
## ``mountUiHot`` entries), the mount handle's identity and the reactive
## root all stayed exactly as they were. A reload that re-mounted would
## also change the text.

when not defined(isonimHmr):
  {.error: "test_native_hmr_tui must be compiled with -d:isonimHmr. " &
      "Without the flag isonim/native/hmr has no registry, no slots and " &
      "no agent callbacks, and every assertion below would be about the " &
      "build-once fallback. " &
      "Run: nim c -r -d:isonimHmr tests/test_native_hmr_tui.nim".}

import std/strutils
import unittest

import isonim_tui/renderer
import isonim_tui/testing/harness
import isonim_tui/testing/snapshot/plaintext as snapPlain

import isonim/native/hmr
import isonim/core/signals

# The stub lives in `isonim` because NH-M2 makes it a cross-repo contract
# (Reprobuild HLX-M8 conforms to that path). Reached by relative path
# rather than copied: two copies would drift, and the copy here would not
# be the one HLX-M8 reads.
import ../../isonim/tests/helpers/hcr_stub

const
  slotHeader = "tui_demo.nim:9:2"
  slotBody = "tui_demo.nim:21:2"
  clickId = "tui_demo.nim:11:8"

var h: TerminalTestHarness
var headerVersion = 1
var bodyVersion = 1
var headerBuilds = 0
var bodyBuilds = 0
var clicks: Signal[int] = nil

proc labelNode(r: TerminalRenderer; text: string): TerminalNode =
  let n = r.createElement("div")
  let line = r.createElement("span")
  r.appendChild(line, r.createTextNode(text))
  r.appendChild(n, line)
  n

proc makeHeader(version: int): UiSlotFactory =
  uiSlotFactory(proc(): TerminalNode =
    inc headerBuilds
    let c = hmrSignalImpl[int](clickId, 0)
    clicks = c
    labelNode(h.renderer, "HEAD" & $version & "-" & $c.val))

proc makeBody(version: int): UiSlotFactory =
  uiSlotFactory(proc(): TerminalNode =
    inc bodyBuilds
    labelNode(h.renderer, "BODY" & $version))

proc demoEntry() =
  hmrRegisterFactory(slotHeader, "hdr" & $headerVersion, makeHeader(headerVersion))
  hmrRegisterFactory(slotBody, "bdy" & $bodyVersion, makeBody(bodyVersion))

proc demoRoot(): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.appendChild(root, hmrInvokeSlot[TerminalNode](slotHeader))
  r.appendChild(root, hmrInvokeSlot[TerminalNode](slotBody))
  root

proc screenText(): string =
  snapPlain.encodePlaintext(h.screenBuffer())

suite "NH-M2: mountUiHot end-to-end on the TUI renderer":

  test "test_native_hmr_tui_reload_repaints_without_remounting":
    h = newTerminalTestHarness(40, 8)
    headerVersion = 1
    bodyVersion = 1
    headerBuilds = 0
    bodyBuilds = 0
    let stub = installHcrStub()
    let root = newHmrRoot(demoEntry)
    root.start()

    let mountsBefore = uiHotMounts
    let mount = mountUiHot(proc(): TerminalNode = demoRoot(),
                           NativeRootMount[TerminalNode](proc(n: TerminalNode) =
                             h.mountTree(n)))
    check uiHotMounts == mountsBefore + 1
    let handleAtMount = mount.handle
    let rootNodeAtMount = h.root

    let firstFrame = screenText()
    check contains(firstFrame, "HEAD1-0")
    check contains(firstFrame, "BODY1")
    check headerBuilds == 1
    check bodyBuilds == 1

    # Component state written by the running app …
    clicks.val = 3
    # … does not repaint on its own: the body's reads are untracked, which
    # is the dynamic-accessor rule. This is also what makes the repaint
    # below attributable to the reload and to nothing else.
    check screenText() == firstFrame

    # The developer edits the header's ui block. Reprobuild would patch
    # the body and fire the callbacks; the stub fires the same callbacks
    # through the same `rb_hcr_apply_reload` entry point.
    headerVersion = 2
    stub.queuePatch(HcrStubPatch(changedFiles: @["tui_demo.nim"],
                                 changedTypes: @[]))
    check rbHcrWantsReload()
    rbHcrApplyReload()

    let secondFrame = screenText()
    # The screen buffer changed …
    check secondFrame != firstFrame
    check contains(secondFrame, "HEAD2-3")     # new body, preserved state
    check not contains(secondFrame, "HEAD1")
    # … the untouched block is still painted, and its body never re-ran …
    check contains(secondFrame, "BODY1")
    check bodyBuilds == 1
    # … and NOTHING re-mounted.
    check uiHotMounts == mountsBefore + 1
    check mount.handle == handleAtMount
    check not mount.isDisposed()
    check root.appliedReloads == 1
    check root.failedReloads == 0

    # The mounted root node did change identity (the parent rebuilt), but
    # the reactive root and the mount handle did not — which is precisely
    # the distinction NH-M1's seam exists to make.
    check h.root != rootNodeAtMount

    mount.dispose()
    root.stop()
    stub.uninstall()
    h.dispose()

  test "test_native_hmr_tui_failed_reload_leaves_the_painted_screen_intact":
    h = newTerminalTestHarness(40, 8)
    headerVersion = 1
    bodyVersion = 1
    headerBuilds = 0
    bodyBuilds = 0
    let stub = installHcrStub()
    var errors: seq[string] = @[]
    let root = newHmrRoot(
      proc() =
        hmrRegisterFactory(slotHeader, "hdr" & $headerVersion,
                           makeHeader(headerVersion))
        if headerVersion >= 2:
          raise newException(ValueError, "broken ui block")
        hmrRegisterFactory(slotBody, "bdy" & $bodyVersion, makeBody(bodyVersion)),
      proc(loc: string; err: ref Exception) = errors.add(err.msg))
    root.start()

    let mount = mountUiHot(proc(): TerminalNode = demoRoot(),
                           NativeRootMount[TerminalNode](proc(n: TerminalNode) =
                             h.mountTree(n)))
    let goodFrame = screenText()
    check contains(goodFrame, "HEAD1-0")
    check contains(goodFrame, "BODY1")
    let rootNodeBefore = h.root
    let headerBuildsBefore = headerBuilds

    headerVersion = 2
    stub.queuePatch(HcrStubPatch(changedFiles: @["tui_demo.nim"],
                                 changedTypes: @[]))
    rbHcrApplyReload()

    # The reload really was attempted …
    check root.beforeReloads == 1
    check root.afterReloads == 1
    check root.failedReloads == 1
    check root.appliedReloads == 0
    check errors.len == 1
    # … and the surface never blanked: byte-identical painted grid, same
    # mounted root object, no extra body evaluation.
    check screenText() == goodFrame
    check h.root == rootNodeBefore
    check headerBuilds == headerBuildsBefore
    check contains(screenText(), "HEAD1-0")

    mount.dispose()
    root.stop()
    stub.uninstall()
    h.dispose()

  test "test_control_tui_reload_with_no_hash_change_leaves_the_frame_identical":
    # DISCRIMINATION CONTROL. The whole lifecycle runs — callbacks fire,
    # the entry re-registers both slots — but no hash moves. If the frame
    # changed here, the first case would be measuring "a reload ran",
    # not "a changed ui block reached the surface".
    h = newTerminalTestHarness(40, 8)
    headerVersion = 1
    bodyVersion = 1
    headerBuilds = 0
    bodyBuilds = 0
    let stub = installHcrStub()
    let root = newHmrRoot(demoEntry)
    root.start()
    let mount = mountUiHot(proc(): TerminalNode = demoRoot(),
                           NativeRootMount[TerminalNode](proc(n: TerminalNode) =
                             h.mountTree(n)))
    let firstFrame = screenText()
    let rootNodeBefore = h.root
    let rendersBefore = mount.handle.renders

    stub.queuePatch(HcrStubPatch(changedFiles: @["tui_demo.nim"],
                                 changedTypes: @[]))
    rbHcrApplyReload()

    check root.appliedReloads == 1        # the reload did happen
    check headerBuilds == 1               # …and rebuilt nothing
    check bodyBuilds == 1
    check mount.handle.renders == rendersBefore
    check screenText() == firstFrame
    check h.root == rootNodeBefore

    mount.dispose()
    root.stop()
    stub.uninstall()
    h.dispose()
