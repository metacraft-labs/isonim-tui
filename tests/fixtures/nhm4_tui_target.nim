## NH-M4 — the real IsoNim TUI application the real Reprobuild HCR agent
## patches.
##
## This is an APPLICATION, not a harness. It links the real
## `librepro_hcr_agent`, installs IsoNim's two agent callbacks through
## `isonim/native/hcr`'s shipped wrappers (via `HmrRoot.start`), mounts a real
## terminal tree with `mountUiHot`, and drives reloads from its own frame loop
## with `pumpReload` — HCR-Overview §13.6's synchronized poll. It is built by
## `tests/test_real_agent_tui_hmr_cycle.nim`, which is the coordinator side.
##
## Nothing here is a double. `TerminalTestHarness` is isonim-tui's real
## headless stack (real `TerminalRenderer`, real style engine, real layout,
## real compositor, real `HeadlessDriver`, real `ScreenBuffer`), the registry
## and slot memos are the production objects from `isonim/native/hmr`, and the
## reconciler is this repo's production `newTuiReconciler()`. The agent is the
## real one: the ten `rb_hcr_*` symbols resolve into `librepro_hcr_agent.so`
## and the lifecycle is driven by a real patch arriving on a real Unix socket.
##
## ## What it REPORTS, and why it reports observations rather than verdicts
##
## Everything this process prints is something it OBSERVED: the painted cell
## grid (base64 of `encodePlaintext(h.screenBuffer())`, so the harness can
## compare bytes without any escaping question), the value the patched leaf
## returned when sampled inside each callback, the slot hash, the reconciler's
## own `ReconcileStats` census, and the identity of the mounted root node. The
## harness decides what is a pass. A target that cannot honour its own
## contract exits non-zero with a named reason rather than printing an empty
## result — "the shim linked and nothing happened" is the silent self-pass
## this campaign keeps finding.
##
## ## The observation that discriminates
##
## `Patch-Loading-Lifecycle.md` §3.1 puts Phase E (before-reload) strictly
## before Phase F/G (load, trampolines) and Phase H (after-reload) strictly
## after. So the two hooks below CALL the patched leaf rather than incrementing
## a counter: under the normative order the before-hook must see the old return
## value and the after-hook the new one. A gate that only counted callbacks
## would pass under either ordering — the defect NH-M2 shipped.
##
## ## Frame provenance, stated exactly
##
## The frame is the TUI's real cell grid: `h.flush()` runs the real style
## cascade, the real layout pass and the real compositor, which writes into the
## real `HeadlessDriver`'s `ScreenBuffer`. It is a character grid, not a pixel
## raster, and it is not the `isonim-examples-tui-term` D/M/P bridge transport.
## What it is NOT is a synthetic raster derived from the tree: the cells come
## from a paint.

when not defined(isonimHmr):
  {.error: "nhm4_tui_target must be compiled with -d:isonimHmr. Without " &
      "the flag isonim/native/hmr has no registry, no slots and no agent " &
      "callbacks, so the reload this target exists to observe could not " &
      "happen and it would report that nothing fired.".}

when not defined(reprobuildHcr):
  {.error: "nhm4_tui_target must be compiled with -d:reprobuildHcr. " &
      "Without the flag isonim/native/hcr compiles its no-op fallback " &
      "bodies, `rb_hcr_before_reload` would register nothing with anything, " &
      "and this target would poll a real agent it is not linked to.".}

import std/[base64, os, strutils, tables]

import isonim_tui/renderer
import isonim_tui/reconciler
import isonim_tui/testing/harness
import isonim_tui/testing/snapshot/plaintext as snapPlain

import isonim/core/signals
import isonim/native/hmr
import isonim/native/reconciler

import ./nhm4_hot_header

# ---------------------------------------------------------------------------
# The agent's own control surface.
#
# `repro_hcr_agent_*` is the coordinator/daemon API, not the ten-function
# application ABI IsoNim binds, so it is declared HERE rather than in
# `isonim/native/hcr` — an embedding host does exactly this. NH-M5 settled the
# header and library names; both come from IsoNim's own `passL` pragma and the
# `--cincludes` the harness passes.
# ---------------------------------------------------------------------------

type
  ReproHcrAgentSymbol {.importc: "repro_hcr_agent_symbol",
                        header: "repro_hcr_agent.h", bycopy.} = object
    name {.importc: "name".}: cstring
    address {.importc: "address".}: pointer

proc reproHcrAgentDefaultSupportProfile(): cstring
  {.importc: "repro_hcr_agent_default_support_profile",
    header: "repro_hcr_agent.h".}

proc reproHcrAgentStartPollingFromEnv(supportProfile: cstring;
                                      symbols: ptr ReproHcrAgentSymbol;
                                      symbolCount: csize_t): cint
  {.importc: "repro_hcr_agent_start_polling_from_env",
    header: "repro_hcr_agent.h".}

proc reproHcrAgentPollNonblocking(): cint
  {.importc: "repro_hcr_agent_poll_nonblocking",
    header: "repro_hcr_agent.h".}

proc reproHcrAgentSetSynchronizedMode(enabled: cint)
  {.importc: "repro_hcr_agent_set_synchronized_mode",
    header: "repro_hcr_agent.h".}

proc reproHcrRbLifecycleTrace(): cstring
  {.importc: "repro_hcr_rb_lifecycle_trace", header: "repro_hcr_agent.h".}

proc reproHcrRbLastCodeSwapped(): cint
  {.importc: "repro_hcr_rb_last_code_swapped", header: "repro_hcr_agent.h".}

# ---------------------------------------------------------------------------
# The demo application
# ---------------------------------------------------------------------------

const
  SlotHeader = "nhm4_demo.nim:11:2"
  SlotBody = "nhm4_demo.nim:23:2"
  ClickId = "nhm4_demo.nim:13:10"
  ChangedFile = "nhm4_hot_header.nim"
  AbsentFile = "nhm4_never_in_any_patch.nim"
  ManagedType = "isonim.UiSlot"
  SchemaId = "isonim.nhm4.tui-real-agent-target-result.v1"

var h: TerminalTestHarness
var headerBuilds = 0
var bodyBuilds = 0
var clicks: Signal[int] = nil

var readVersion: proc(): cint {.noinline, noSideEffect, gcsafe.} =
  nhm4HeaderVersion
  ## Called through a variable so neither Nim nor the C compiler can fold two
  ## calls into one or constant-fold either. Note which way a folding mistake
  ## would fail: every assertion downstream wants the two calls to differ, so
  ## folding could only turn the gate red, never falsely green.

proc headerVersion(): int = int(readVersion())

proc keyed(tag, key: string; text = ""): TerminalNode =
  result = h.renderer.createElement(tag)
  h.renderer.setAttribute(result, IsonimKeyAttr, key)
  if text.len > 0:
    h.renderer.setTextContent(result, text)

proc makeHeader(version: int): UiSlotFactory =
  uiSlotFactory(proc(): TerminalNode =
    inc headerBuilds
    let c = hmrSignalImpl[int](ClickId, 0)
    clicks = c
    keyed("div", "header", "HEAD" & $version & "-" & $c.val))

proc makeBody(): UiSlotFactory =
  ## The slot the edit does NOT touch. Its hash never moves, so its node must
  ## survive every reload — and its build counter must not advance.
  uiSlotFactory(proc(): TerminalNode =
    inc bodyBuilds
    keyed("div", "body", "BODYSTABLE"))

proc demoEntry() =
  ## The ui-block registration pass. `HmrRoot` re-runs this inside
  ## `rb_hcr_after_reload` — Phase H, the first point at which a call reaches
  ## the patched body — so `headerVersion()` here reads POST-swap code.
  let v = headerVersion()
  hmrRegisterFactory(SlotHeader, "hdr" & $v, makeHeader(v))
  hmrRegisterFactory(SlotBody, "bdy1", makeBody())

proc demoRoot(): TerminalNode =
  let root = keyed("div", "root")
  h.renderer.appendChild(root, hmrInvokeSlot[TerminalNode](SlotHeader))
  h.renderer.appendChild(root, hmrInvokeSlot[TerminalNode](SlotBody))
  root

proc childByKey(n: TerminalNode; key: string): TerminalNode =
  if n == nil: return nil
  for c in n.children:
    if c.attributes.getOrDefault(IsonimKeyAttr) == key: return c
  nil

# ---------------------------------------------------------------------------
# The live tree, and the reconciler that keeps it alive
# ---------------------------------------------------------------------------

var tuiRec: RendererReconciler[TerminalNode]
var liveRoot: TerminalNode = nil
var liveMounted = false
var reconcilePasses = 0
var lastStats = ReconcileStats()

proc mountOrReconcile(node: TerminalNode) =
  ## The mount seam's sink. The FIRST build is mounted; every later one is a
  ## CANDIDATE that the production reconciler folds into the live tree, so the
  ## visible widget is updated in place and `h.root` never changes identity.
  ##
  ## This is deliberately not `mountUiHot`'s renderer overload, which removes
  ## the mounted child and appends the new one — that would repaint the right
  ## text while telling you nothing about reconciliation.
  if not liveMounted:
    liveRoot = node
    liveMounted = true
    h.mountTree(liveRoot)
    return
  var stats = ReconcileStats()
  liveRoot = tuiRec.reconcile(liveRoot, node, stats)
  lastStats = stats
  inc reconcilePasses
  h.root = liveRoot
  h.flush()

proc frame(): string = snapPlain.encodePlaintext(h.screenBuffer())

# ---------------------------------------------------------------------------
# Per-reload observations
# ---------------------------------------------------------------------------

type
  HookSample = object
    fired: bool
    version: int
    changedFiles: int
    changedTypes: int
    firstType: string
    firstTypeOldSize: uint32
    firstTypeNewSize: uint32
    fileChangedProbe: bool
    fileChangedAbsent: bool
    typeChangedProbe: bool

var beforeSample: HookSample
var afterSample: HookSample

proc sample(info: HmrReloadInfo): HookSample =
  result.fired = true
  result.version = headerVersion()
  result.changedFiles = info.changedFiles.len
  result.changedTypes = info.changedTypes.len
  if info.changedTypes.len > 0:
    result.firstType = info.changedTypes[0].typeName
    result.firstTypeOldSize = info.changedTypes[0].oldSize
    result.firstTypeNewSize = info.changedTypes[0].newSize
  result.fileChangedProbe = rbHcrFileChanged(ChangedFile.cstring)
  result.fileChangedAbsent = rbHcrFileChanged(AbsentFile.cstring)
  result.typeChangedProbe = rbHcrTypeChanged(ManagedType.cstring)

proc jsonBool(v: bool): string = (if v: "true" else: "false")

proc emitSample(name: string; s: HookSample): string =
  "\"" & name & "\":{" &
    "\"fired\":" & jsonBool(s.fired) &
    ",\"version\":" & $s.version &
    ",\"changedFilesCount\":" & $s.changedFiles &
    ",\"changedTypesCount\":" & $s.changedTypes &
    ",\"firstType\":\"" & s.firstType & "\"" &
    ",\"firstTypeOldSize\":" & $s.firstTypeOldSize &
    ",\"firstTypeNewSize\":" & $s.firstTypeNewSize &
    ",\"fileChangedProbe\":" & jsonBool(s.fileChangedProbe) &
    ",\"fileChangedAbsent\":" & jsonBool(s.fileChangedAbsent) &
    ",\"typeChangedProbe\":" & jsonBool(s.typeChangedProbe) & "}"

proc emitStats(s: ReconcileStats): string =
  "{\"placed\":" & $s.placed & ",\"moved\":" & $s.moved &
    ",\"removed\":" & $s.removed & ",\"propUpdates\":" & $s.propUpdates &
    ",\"matched\":" & $s.matched & ",\"replaced\":" & $s.replaced &
    ",\"touched\":" & $s.touched & "}"

proc die(reason: string; code: int) {.noreturn.} =
  stderr.writeLine("nhm4_tui_target: " & reason)
  quit(code)

# ---------------------------------------------------------------------------

proc main() =
  var markerPath = ""
  var jsonOutPath = ""
  var wantReloads = 1
  var pollBudget = 30000
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--marker="): markerPath = arg["--marker=".len .. ^1]
    elif arg.startsWith("--json-out="):
      jsonOutPath = arg["--json-out=".len .. ^1]
    elif arg.startsWith("--reloads="):
      wantReloads = parseInt(arg["--reloads=".len .. ^1])
    elif arg.startsWith("--poll-budget="):
      pollBudget = parseInt(arg["--poll-budget=".len .. ^1])
    else:
      die("unknown argument: " & arg, 4)
  if markerPath.len == 0 or jsonOutPath.len == 0:
    die("--marker= and --json-out= are both required", 4)

  h = newTerminalTestHarness(44, 8)
  tuiRec = newTuiReconciler()

  # Synchronized mode (Patch-Loading-Lifecycle.md §3.4): the agent parks the
  # request and this process's own loop applies it, so both callbacks run on
  # the thread that owns the terminal tree. An automatic-mode agent would run
  # them on its detached thread and mutate the tree from under the frame loop.
  reproHcrAgentSetSynchronizedMode(1)

  let root = newHmrRoot(demoEntry)
  var slotErrors: seq[string] = @[]
  root.onError = proc(loc: string; err: ref Exception) =
    slotErrors.add(loc & ": " & err.msg)
  root.onBeforeReload = proc(info: HmrReloadInfo) =
    beforeSample = sample(info)
  root.onAfterReload = proc(info: HmrReloadInfo) =
    afterSample = sample(info)
  root.start()

  let mountsBefore = uiHotMounts
  let mount = mountUiHot(proc(): TerminalNode = demoRoot(),
                         NativeRootMount[TerminalNode](mountOrReconcile))
  let handleAtMount = mount.handle
  let rootNodeAtMount = h.root
  let initialFrame = frame()
  let initialVersion = headerVersion()
  if not initialFrame.contains("HEAD1-0"):
    die("the pre-patch frame does not contain HEAD1-0; the fixture never " &
        "painted what it was written to paint:\n" & initialFrame, 5)

  # Component state written by the running app. The body's reads are
  # untracked (the dynamic-accessor rule), so this does NOT repaint on its
  # own — which is also what makes the repaint after the reload attributable
  # to the reload and to nothing else.
  clicks.val = 3
  if frame() != initialFrame:
    die("writing a preserved signal repainted on its own; the reload's " &
        "repaint would not be attributable", 5)

  var symbols: array[1, ReproHcrAgentSymbol]
  symbols[0].name = Nhm4HeaderSymbol.cstring
  symbols[0].address = cast[pointer](nhm4HeaderVersion)
  let startRc = reproHcrAgentStartPollingFromEnv(
    reproHcrAgentDefaultSupportProfile(), addr symbols[0], 1.csize_t)
  if startRc != 0:
    die("repro_hcr_agent_start_polling_from_env returned " & $startRc, 6)

  # The marker is the coordinator's signal that a BEFORE exists: it was
  # written after the first frame was painted and read back.
  writeFile(markerPath, "nhm4-ready\n")

  var cycles: seq[string] = @[]
  var polls = 0
  var seenReloads = 0
  while polls < pollBudget and cycles.len < wantReloads:
    discard reproHcrAgentPollNonblocking()
    let afterReloadsBefore = root.afterReloads
    beforeSample = HookSample()
    afterSample = HookSample()
    discard root.pumpReload()
    if root.afterReloads > afterReloadsBefore:
      inc seenReloads
      var rec = "{\"index\":" & $seenReloads
      rec.add ",\"frame\":\"" & encode(frame()) & "\""
      rec.add ",\"versionAfterCycle\":" & $headerVersion()
      rec.add ",\"slotHashHeader\":\"" & root.slotHash(SlotHeader) & "\""
      rec.add ",\"slotHashBody\":\"" & root.slotHash(SlotBody) & "\""
      rec.add ",\"headerBuilds\":" & $headerBuilds
      rec.add ",\"bodyBuilds\":" & $bodyBuilds
      rec.add ",\"renders\":" & $mount.handle.renders
      rec.add ",\"reconcilePasses\":" & $reconcilePasses
      rec.add ",\"reconcileStats\":" & emitStats(lastStats)
      rec.add ",\"rootNodeIsMountNode\":" &
        jsonBool(h.root == rootNodeAtMount)
      rec.add ",\"rootNodeIsLiveRoot\":" & jsonBool(h.root == liveRoot)
      let headerNow = h.root.childByKey("header")
      let bodyNow = h.root.childByKey("body")
      rec.add ",\"headerNodeId\":" &
        $(if headerNow == nil: -1 else: headerNow.id)
      rec.add ",\"bodyNodeId\":" & $(if bodyNow == nil: -1 else: bodyNow.id)
      rec.add ",\"appliedReloads\":" & $root.appliedReloads
      rec.add ",\"failedReloads\":" & $root.failedReloads
      rec.add ",\"beforeReloads\":" & $root.beforeReloads
      rec.add ",\"afterReloads\":" & $root.afterReloads
      rec.add ",\"uiHotMounts\":" & $uiHotMounts
      rec.add ",\"mountHandleStable\":" & jsonBool(mount.handle == handleAtMount)
      rec.add ",\"mountDisposed\":" & jsonBool(mount.isDisposed())
      rec.add ",\"mountErrors\":" & $mount.errors
      rec.add ",\"slotErrors\":" & $slotErrors.len
      rec.add ",\"lifecycleTrace\":\"" & $reproHcrRbLifecycleTrace() & "\""
      rec.add ",\"codeSwapped\":" & jsonBool(reproHcrRbLastCodeSwapped() != 0)
      rec.add ",\"fileChangedAtEnd\":" &
        jsonBool(rbHcrFileChanged(ChangedFile.cstring))
      rec.add "," & emitSample("observedInBefore", beforeSample)
      rec.add "," & emitSample("observedInAfter", afterSample)
      rec.add "}"
      cycles.add rec
    inc polls
    sleep(1)

  if cycles.len < wantReloads:
    # Loud. A target that printed a short result here would read as "the
    # agent linked and nothing happened".
    die("only " & $cycles.len & " of " & $wantReloads &
        " reload cycles were observed within " & $pollBudget & " polls", 3)

  var doc = "{\"schemaId\":\"" & SchemaId & "\""
  doc.add ",\"startRc\":" & $startRc
  doc.add ",\"polls\":" & $polls
  doc.add ",\"cols\":" & $h.cols & ",\"rows\":" & $h.rows
  doc.add ",\"initialFrame\":\"" & encode(initialFrame) & "\""
  doc.add ",\"initialVersion\":" & $initialVersion
  doc.add ",\"initialSlotHashHeader\":\"" & "hdr" & $initialVersion & "\""
  doc.add ",\"uiHotMountsBefore\":" & $mountsBefore
  doc.add ",\"rootNodeIdAtMount\":" &
    $(if rootNodeAtMount == nil: -1 else: rootNodeAtMount.id)
  let headerAtMount = rootNodeAtMount.childByKey("header")
  let bodyAtMount = rootNodeAtMount.childByKey("body")
  doc.add ",\"headerNodeIdAtMount\":" &
    $(if headerAtMount == nil: -1 else: headerAtMount.id)
  doc.add ",\"bodyNodeIdAtMount\":" &
    $(if bodyAtMount == nil: -1 else: bodyAtMount.id)
  doc.add ",\"cycles\":[" & cycles.join(",") & "]"
  doc.add ",\"finalFrame\":\"" & encode(frame()) & "\""
  doc.add ",\"hcrAgentHooksInstalled\":" & jsonBool(hcrAgentHooks != nil)
  doc.add "}"
  writeFile(jsonOutPath, doc)

  mount.dispose()
  root.stop()
  h.dispose()

main()
