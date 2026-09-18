## NH-M3 — ``test_tui_reconciler_preserves_identity_on_unchanged_subtree``
##
## Stub-driven: a real reload is performed through the HCR agent seam,
## the entry call re-registers the ui slots, and the reconciler is then
## asked to fold the rebuilt tree into the live one. The assertion is on
## the ``TerminalNode`` REFERENCE that survives.
##
## MOCK POLICY (workspace rule: every mock justified in the header).
## Exactly ONE double — ``isonim/tests/helpers/hcr_stub.nim``, the
## Reprobuild HCR agent — justified at length in that file: the shipped
## ``librepro_hcr_agent`` exports the ten ``rb_hcr_*`` symbols with
## baseline bodies that never fire a callback, and live dispatch is
## Reprobuild HLX-M8, which is ``planned``. Linking the real library
## would exercise the reload lifecycle zero times.
##
## Everything else is the production object: isonim-tui's real
## ``TerminalRenderer`` and ``TerminalNode``, the real slot registry and
## memos from ``isonim/native/hmr``, and the real reconciler from
## ``isonim/native/reconciler`` driven through this repo's own instance
## (``isonim_tui/reconciler``).
##
## NO SKIP ARMS. Everything here is in-process; there is no TTY, no
## display and no device to probe for.
##
## ## Why the assertions do not look at the screen
##
## The TUI compositor diffs at cell level, so a subtree that was
## destroyed and rebuilt identically paints identically. **A screen
## comparison cannot fail for the defect this gate exists to catch.**
## What a reconciler preserves in a terminal is the ``TerminalNode``
## itself — and with it the focus target, the selection, the scroll
## offset and every registered event handler, all of which hang off that
## object. So every assertion below is on a node reference or on the
## ``ReconcileStats`` census of renderer calls, and never on rendered
## text.
##
## ## Discrimination
##
## Each "preserves X" case is paired with a measured control that runs
## the SAME predicate over the SAME trees with an always-replace
## reconciler (one whose ``identityKey`` never repeats). One predicate,
## two subjects — `Verification-Harness-Traps` §30 — and the control is
## asserted to FAIL the preservation it is the control for, so it is not
## a self-comparison wearing a negation (§7b).

when not defined(isonimHmr):
  {.error: "test_tui_reconciler_identity must be compiled with " &
      "-d:isonimHmr. Without the flag isonim/native/hmr has no registry " &
      "and no slots, so the 'reload' this file drives would not happen " &
      "and every assertion would be about a tree that was never rebuilt. " &
      "Run: nim c -r -d:isonimHmr tests/test_tui_reconciler_identity.nim".}

import std/[tables, strutils]
import unittest

import isonim_tui/renderer
import isonim_tui/reconciler

import isonim/native/hmr
import isonim/native/reconciler

import ../../isonim/tests/helpers/hcr_stub

const
  slotHeader = "tui_recon_demo.nim:9:2"
  slotRows = "tui_recon_demo.nim:21:2"

var r: TerminalRenderer
var headerVersion = 1
var rowsVersion = 1

proc keyed(tag, key: string; text: string = ""): TerminalNode =
  result = r.createElement(tag)
  r.setAttribute(result, IsonimKeyAttr, key)
  if text.len > 0:
    r.setTextContent(result, text)

proc makeHeader(version: int): UiSlotFactory =
  uiSlotFactory(proc(): TerminalNode =
    keyed("div", "header", "HEAD" & $version))

proc makeRows(version: int): UiSlotFactory =
  ## Three keyed rows. The middle one carries the version, so a hash
  ## change edits exactly one leaf inside this block and leaves its two
  ## siblings byte-identical — which is what makes "the unchanged parts
  ## of a CHANGED block also keep their identity" measurable rather than
  ## merely claimed.
  uiSlotFactory(proc(): TerminalNode =
    let rows = keyed("div", "rows")
    r.appendChild(rows, keyed("div", "rowA", "alpha"))
    r.appendChild(rows, keyed("div", "rowB", "beta" & $version))
    r.appendChild(rows, keyed("div", "rowC", "gamma"))
    rows)

proc demoEntry() =
  hmrRegisterFactory(slotHeader, "hdr" & $headerVersion,
                     makeHeader(headerVersion))
  hmrRegisterFactory(slotRows, "rows" & $rowsVersion, makeRows(rowsVersion))

proc demoRoot(): TerminalNode =
  let root = keyed("div", "root")
  r.appendChild(root, hmrInvokeSlot[TerminalNode](slotHeader))
  r.appendChild(root, hmrInvokeSlot[TerminalNode](slotRows))
  root

proc childByKey(n: TerminalNode; key: string): TerminalNode =
  if n == nil: return nil
  for c in n.children:
    if c.attributes.getOrDefault(IsonimKeyAttr) == key: return c
  nil

proc deepChild(n: TerminalNode; path: varargs[string]): TerminalNode =
  result = n
  for key in path:
    if result == nil: return nil
    result = result.childByKey(key)

var alwaysReplaceCounter = 0

proc newAlwaysReplaceReconciler(): RendererReconciler[TerminalNode] =
  ## The plausible non-reconciler: a fresh identity per call, so nothing
  ## is ever recognised and the tree is rebuilt wholesale.
  result = newTuiReconciler()
  result.nodes.identityKey = proc(n: TerminalNode): NodeIdentity =
    inc alwaysReplaceCounter
    "unmatchable-" & $alwaysReplaceCounter

type ReloadOutcome = object
  rootSurvived: bool
  headerSurvived: bool
  unchangedRowSurvived: bool
  changedRowSurvived: bool
  changedRowText: string
  stats: ReconcileStats

proc runReload(rec: RendererReconciler[TerminalNode];
               bumpRowsHash: bool): ReloadOutcome =
  ## Mount, drive one reload through the stub agent, reconcile, report.
  ## Both the real reconciler and the control go through this, so
  ## neither is graded on its own yardstick.
  r = TerminalRenderer()
  resetNodeIds()
  headerVersion = 1
  rowsVersion = 1
  let stub = installHcrStub()
  let root = newHmrRoot(demoEntry)
  root.start()

  let liveRoot = demoRoot()
  let oldHeader = liveRoot.childByKey("header")
  let oldRowA = liveRoot.deepChild("rows", "rowA")
  let oldRowB = liveRoot.deepChild("rows", "rowB")
  doAssert oldHeader != nil and oldRowA != nil and oldRowB != nil,
    "fixture: the pre-reload tree does not have the shape this test assumes"

  # The reload, driven through the agent's real lifecycle. Only the rows
  # block's hash moves (or nothing does, in the no-change control) — the
  # header's stays put, so its slot memo must not invalidate. The version
  # bump happens inside `applyCodeSwap`, i.e. at Phase G, which is the
  # only point at which the "new bodies" become reachable; bumping it
  # before `rbHcrApplyReload` would make the new body visible to Phase E
  # and the gate would pass under either phase ordering.
  stub.queuePatch(HcrStubPatch(
    changedFiles: @["tui_recon_demo.nim"],
    changedTypes: @[],
    applyCodeSwap: proc() =
      if bumpRowsHash: rowsVersion = 2))
  doAssert rbHcrWantsReload()
  rbHcrApplyReload()
  doAssert root.appliedReloads == 1, "the stub-driven reload did not apply"
  doAssert root.failedReloads == 0

  # The mount seam would call this; the test calls it directly so the
  # rebuilt tree is in hand and can be reconciled explicitly.
  let rebuiltRoot = demoRoot()

  var stats = ReconcileStats()
  let survivingRoot = rec.reconcile(liveRoot, rebuiltRoot, stats)

  ReloadOutcome(
    rootSurvived: survivingRoot == liveRoot,
    headerSurvived: survivingRoot.childByKey("header") == oldHeader,
    unchangedRowSurvived:
      survivingRoot.deepChild("rows", "rowA") == oldRowA,
    changedRowSurvived:
      survivingRoot.deepChild("rows", "rowB") == oldRowB,
    changedRowText:
      (let n = survivingRoot.deepChild("rows", "rowB");
       if n == nil: "" else: n.textContent),
    stats: stats)

suite "NH-M3: TUI reconciler preserves identity":

  test "test_tui_reconciler_preserves_identity_on_unchanged_subtree":
    # One slot's hash changed; the other's did not. The unchanged slot's
    # widget must be the SAME object, and so must every node in the
    # changed slot that the edit did not touch.
    let outcome = newTuiReconciler().runReload(bumpRowsHash = true)
    check outcome.rootSurvived
    check outcome.unchangedRowSurvived
    # The edited row is the same widget with new content — a changed
    # body means new props, not a new widget.
    check outcome.changedRowSurvived
    check outcome.changedRowText.contains("beta2")
    # Exactly one renderer write, on the one leaf that changed. Nothing
    # was placed, moved or removed.
    check outcome.stats.propUpdates == 1
    check outcome.stats.placed == 0
    check outcome.stats.moved == 0
    check outcome.stats.removed == 0

  test "CONTROL: with no reconciler, the same reload loses every reference":
    let outcome = newAlwaysReplaceReconciler().runReload(bumpRowsHash = true)
    check not outcome.rootSurvived
    check not outcome.unchangedRowSurvived
    check not outcome.changedRowSurvived
    check outcome.stats.matched == 0

  test "ATTRIBUTION: the unchanged SLOT's node is the memo's doing, not the reconciler's":
    # Measured 2026-09-18, and recorded because it is easy to credit the
    # wrong mechanism and then "improve" the wrong one. The header slot's
    # hash did not change, so `hmrInvokeSlot` serves its memo and the
    # REBUILT tree already contains the SAME `TerminalNode` — before any
    # reconciliation happens. The header therefore survives under the
    # always-replace control too.
    #
    # What the reconciler is responsible for is everything the memo does
    # not cover: the root (rebuilt on every entry call) and every node
    # INSIDE a slot whose hash DID change. Those are the three fields the
    # two cases above disagree on.
    let real = newTuiReconciler().runReload(bumpRowsHash = true)
    let control = newAlwaysReplaceReconciler().runReload(bumpRowsHash = true)
    check real.headerSurvived
    check control.headerSurvived

  test "a reload in which NO hash changed touches the renderer zero times":
    # The control the milestone's phrasing turns on: "when a slot's hash
    # MATCHES … the reconciler does nothing". Measured as a census of
    # renderer calls, because the painted screen is identical either way.
    let outcome = newTuiReconciler().runReload(bumpRowsHash = false)
    check outcome.rootSurvived
    check outcome.headerSurvived
    check outcome.unchangedRowSurvived
    check outcome.changedRowSurvived
    check outcome.stats.touched == 0
    # Non-vacuity: the pass must have walked a real tree, not returned
    # early. root + header + rows + rowA/B/C + their four text nodes.
    check outcome.stats.matched > 5

  test "the TUI instance satisfies the whole contract":
    # `validate` names a missing operation at the seam instead of letting
    # a nil field surface as a crash several frames into the diff.
    newTuiReconciler().validate()
