## NH-M4 — IsoNim native HMR against the REAL Reprobuild HCR agent.
##
## The milestone's deliverable in one sentence: *developer edits a `.nim` file
## -> Reprobuild recompiles -> the agent applies the patch -> IsoNim re-runs
## the entry -> the reconciler updates the visible widget -> the next frame
## reflects the change.* Every arrow below is a real one.
##
## ## MOCK POLICY — there is no double in this file
##
## NH-M2's TUI gates (`test_native_hmr_tui.nim`) run against
## `isonim/tests/helpers/hcr_stub.nim`, and had to: when they were written the
## shipped `librepro_hcr_agent` exported the ten `rb_hcr_*` symbols with
## baseline bodies that never fired a callback. Reprobuild `HLX-M8` landed the
## real lifecycle on 2026-09-18, so this file uses **no stub at all**:
##
##   * the agent is `librepro_hcr_agent.so`, built here from
##     `reprobuild/libs/repro_hcr_agent/build_lib.sh`;
##   * the coordinator is `reprobuild/scripts/hcr_patch_driver.nim`, which
##     speaks the production `HcrCoordinatorClient` over the production Unix
##     socket IPC and extracts patch bytes with the production HLX-M1 ELF
##     reader — this repo owns no second copy of any of that;
##   * the patch is the output of a real `nim` recompile of a real edit to
##     `tests/fixtures/nhm4_hot_header.nim`;
##   * the application is `tests/fixtures/nhm4_tui_target.nim`, a real process
##     with a real `TerminalTestHarness`, the real slot registry and memos
##     from `isonim/native/hmr`, and this repo's production
##     `newTuiReconciler()`;
##   * the frame is the real `ScreenBuffer` the real compositor painted.
##
## ## NO SKIPS
##
## The gate is `linux and amd64` because the Linux ELF provider is; on any
## other host this file refuses to COMPILE with a message naming the host and
## the covering milestone, rather than compiling to a `skip()` that exits 0. A
## missing `../reprobuild` checkout, a missing `gcc`, a socket path the kernel
## would truncate and a target that never observes a reload are all loud
## failures carrying their remedy.
##
## ## WHAT EACH ARM DISCRIMINATES — measured, never asserted
##
## 1. `test_real_agent_tui_hmr_cycle` — the cycle. Its discriminating
##    observation is not that a callback ran: the two hooks CALL the patched
##    leaf, so under `Patch-Loading-Lifecycle.md` §3.1's phase order the
##    before-hook must read the OLD value and the after-hook the NEW one. That
##    is the NH-M2 defect class — four gates that were green under both
##    orderings — and it is killed here by an actual second build.
##
## 2. `test_control_real_agent_patch_that_changes_nothing_leaves_the_frame_identical`
##    — a REAL patch, really applied (`codeSwapped` true, full
##    `prepare,latch,before,load,trampolines,after` trace) whose recompiled
##    body returns the value it already returned. If the frame moved here,
##    arm 1 would be measuring "a reload ran" rather than "a changed ui block
##    reached the surface". Same binary, same driver, one digit apart in the
##    edited source.
##
## 3. `test_real_agent_tui_multi_edit_session` — the *developer edit loop*,
##    which NH-M4's own text says must not be claimed from a one-edit run.
##    Two successive edits over ONE session, each with its own before/after
##    observation.
##
## 4. `test_real_agent_step38_late_load_failure_cycle` —
##    `Patch-Loading-Lifecycle.md` §3.3 step 38. The refusal is real: the
##    patch body is the >1-page function `hcr_lx_m8_patch_oversize` that
##    Reprobuild's own step-38 gate uses, so both halves of step 38 are
##    provoked by the same bytes, and `repro_hcr_lx_txn_prepare_site` refuses
##    it inside Phase F after before-reload has already fired. A RECOVERY arm
##    runs on the same process immediately afterwards and applies normally, so
##    "nothing moved" is not what this instrument says about every run.
##
## 5. `test_falsifier_inverted_phase_order_breaks_the_cycle` — the same arm-1
##    run against an agent built `-DREPRO_HCR_FALSIFY_BEFORE_RELOAD_AFTER_SWAP`,
##    i.e. firing before-reload AFTER Phase G, the ordering IsoNim's design doc
##    once asked for. Asserted to produce a DIFFERENT observation (the
##    before-hook reads the post-swap value), which is arm 1's key assertion
##    measured going red.
##
## 6. `test_falsifier_skipped_step38_never_reaches_after_reload` — arm 4
##    against an agent built `-DREPRO_HCR_FALSIFY_SKIP_STEP38`. The target
##    then never observes an after-reload for the failed load and exits 3 with
##    its own named reason, which is arm 4's obligation measured going red.
##
## ## WHAT THIS GATE DOES NOT PROVE, stated so it is not over-read
##
## The patched function is a LEAF returning an integer, and the entry pass
## derives the slot hash from its return value. The `{.uiComponent.}`
## compile-time `symBodyHash` is therefore not itself what travels over the
## wire. The reason is measured, not stylistic: the Linux provider's Direct
## Patch Injection path copies the replacement body into a provider-owned page
## and applies NO relocations to it, so a patched Nim body that calls
## `hmrRegisterFactory` cannot be delivered. See the header of
## `tests/fixtures/nhm4_hot_header.nim`.
##
## The renderer is the TUI and the frame is a CHARACTER CELL GRID produced by
## a real paint. It is not a pixel raster, and it is not the
## `isonim-examples-tui-term` D/M/P bridge transport.

when not (defined(linux) and defined(amd64)):
  {.error: "test_real_agent_tui_hmr_cycle is linux-x86_64 only, because " &
      "the Reprobuild HCR provider it drives is (HLX-M0/M1/M8). It refuses " &
      "to compile elsewhere rather than compiling to a skip that exits 0. " &
      "The macOS arm is owned by HCR-Per-Platform-Handoff / HX-S-*; the " &
      "Windows arm by HCR-Windows-PE-Provider.".}

when not defined(isonimHmr):
  {.error: "test_real_agent_tui_hmr_cycle must be compiled with " &
      "-d:isonimHmr: without it the target it builds would carry the " &
      "build-once fallback and every assertion would be about a mount that " &
      "never reloads. Run: just test-real-agent-hmr".}

import std/[base64, json, os, osproc, strutils, strtabs, times]
import unittest

# ---------------------------------------------------------------------------
# Paths and prerequisites
# ---------------------------------------------------------------------------

const
  TargetSymbol = "isonim_nhm4_header_version"
  OversizePatchSymbol = "hcr_lx_m8_patch_oversize"
  ChangedFile = "nhm4_hot_header.nim"
  ManagedTypeSpec = "isonim.UiSlot:16:24"
  SchemaId = "isonim.nhm4.tui-real-agent-target-result.v1"
  FalsifyPhaseOrder = "REPRO_HCR_FALSIFY_BEFORE_RELOAD_AFTER_SWAP"
  FalsifySkipStep38 = "REPRO_HCR_FALSIFY_SKIP_STEP38"
  MaxUnixSocketPath = 100
    ## `sockaddr_un.sun_path` is 108 bytes on Linux. Nim's `bindUnix` raises
    ## "socket path too long" — measured while writing this gate, from a
    ## working directory under a long session scratchpad. A budget checked
    ## here names the cause; the raise from inside the driver does not.

let repoRoot = currentSourcePath().parentDir().parentDir()
let workspaceRoot = repoRoot.parentDir()
let reproRoot = workspaceRoot / "reprobuild"
let fixtureDir = repoRoot / "tests" / "fixtures"
let hotHeaderPath = fixtureDir / "nhm4_hot_header.nim"
let buildRoot = repoRoot / "build" / "nhm4-real-agent"

proc fail(reason: string) =
  ## Loud, and never a skip. Every caller passes a remedy.
  raise newException(IOError, "NH-M4 real-agent gate: " & reason)

proc shellQuote(args: openArray[string]): string =
  for i, a in args:
    if i > 0: result.add " "
    result.add quoteShell(a)

proc runOrFail(args: openArray[string]; cwd: string): string =
  let cmd = shellQuote(args)
  let res = execCmdEx(cmd, workingDir = cwd)
  if res.exitCode != 0:
    fail("command failed (exit " & $res.exitCode & "): " & cmd & "\n" &
         res.output)
  res.output

proc requirePrerequisites() =
  if findExe("gcc").len == 0:
    fail("gcc is not on PATH. It builds librepro_hcr_agent and the step-38 " &
         "oversize patch body. Run inside the dev shell: " &
         "direnv exec " & repoRoot & " just test-real-agent-hmr")
  if not dirExists(reproRoot):
    fail("the reprobuild checkout is missing at " & reproRoot & ". This " &
         "gate links the REAL agent and drives the REAL coordinator; there " &
         "is no stub arm. Remedy: repro ws enable reprobuild (or clone it " &
         "beside this repo) and re-run.")
  let agentC = reproRoot / "libs" / "repro_hcr_agent" / "c" /
    "repro_hcr_agent.h"
  if not fileExists(agentC):
    fail("expected the agent header at " & agentC & " and it is not there. " &
         "NH-M5 settled the name; a reprobuild checkout without it is too " &
         "old for this gate.")
  if not fileExists(hotHeaderPath):
    fail("the editable fixture is missing at " & hotHeaderPath)

# ---------------------------------------------------------------------------
# Build steps
# ---------------------------------------------------------------------------

proc agentLibName(): string =
  ## The agent build script's own answer, not this gate's guess, so the two
  ## cannot disagree about the artifact name (the NH-M5 lesson).
  runOrFail([reproRoot / "libs" / "repro_hcr_agent" / "build_lib.sh",
             "--print-name"], reproRoot).strip()

proc buildAgentLibrary(outDir: string; defines: openArray[string] = []): string =
  ## Returns the DIRECTORY, which is what goes on `-L` / `-rpath`.
  createDir(outDir)
  var args = @[reproRoot / "libs" / "repro_hcr_agent" / "build_lib.sh", outDir]
  for d in defines: args.add "--define=" & d
  discard runOrFail(args, reproRoot)
  let lib = outDir / agentLibName()
  if not fileExists(lib) or getFileSize(lib) <= 0:
    fail("build_lib.sh reported success but produced nothing at " & lib)
  outDir

proc buildDriver(): string =
  ## `reprobuild/scripts/hcr_patch_driver.nim` — the production coordinator,
  ## compiled from the reprobuild checkout so this repo owns no copy of the
  ## HCR wire protocol or of the ELF patch-byte reader.
  result = buildRoot / "bin" / "hcr_patch_driver"
  let src = reproRoot / "scripts" / "hcr_patch_driver.nim"
  if not fileExists(src):
    fail("the coordinator is missing at " & src & ". Without it this gate " &
         "would have to re-implement the HCR wire protocol, which is the " &
         "two-copies-of-one-predicate trap.")
  createDir(parentDir(result))
  discard runOrFail(["nim", "c", "--hints:off", "--warnings:off",
                     "--nimcache:" & (buildRoot / "nimcache" / "driver"),
                     "-o:" & result, src], reproRoot)
  if not fileExists(result):
    fail("the coordinator did not build at " & result)

proc patchableFlags(): seq[string] =
  ## The patchable build profile.
  ##
  ## SECOND COPY, and it is one — reprobuild's own `patchableCompileFlags`
  ## (`repro_project_dsl`) is the authority, and this repo cannot import it
  ## without taking on that library's whole dependency closure. Recorded rather
  ## than hidden, and the divergence it could cause is caught rather than
  ## trusted: a target built without the sled is refused `absent-sled` at
  ## prepare, so the healthy arms would fail with a REFUSAL rather than a
  ## reload. What makes that legible instead of mysterious is that every arm
  ## asserts the lifecycle trace it expected, and `prepare,reject` is not
  ## `prepare,latch,before,load,trampolines,after`.
  @["-fpatchable-function-entry=16,0", "-falign-functions=16",
    "-fcf-protection=full", "-ftls-model=global-dynamic"]

proc buildTarget(libDir, outName: string): string =
  result = buildRoot / "bin" / outName
  createDir(parentDir(result))
  var args = @["nim", "c", "--hints:off", "--warnings:off",
               "--styleCheck:usages", "--styleCheck:error",
               "--mm:orc", "--threads:on", "-d:release",
               "-d:isonimHmr", "-d:reprobuildHcr",
               "--nimcache:" & (buildRoot / "nimcache" / outName),
               "--passC:-I" & (reproRoot / "libs" / "repro_hcr_agent" / "c")]
  for f in patchableFlags(): args.add "--passC:" & f
  args.add ["--passL:-L" & libDir,
            "--passL:-Wl,-rpath," & libDir,
            "--passL:-Wl,--build-id=sha1",
            "-o:" & result,
            fixtureDir / "nhm4_tui_target.nim"]
  discard runOrFail(args, repoRoot)
  if not fileExists(result):
    fail("the target did not build at " & result)
  # Anti-vacuity: the link must be satisfied by the agent library, and the ten
  # rb_hcr_* symbols must be UNDEFINED in the image (i.e. resolved from it),
  # not compiled away by the flag-off fallback.
  let nmOut = execCmdEx("nm -u " & quoteShell(result)).output
  for sym in ["rb_hcr_wants_reload", "rb_hcr_apply_reload",
              "rb_hcr_before_reload", "rb_hcr_after_reload",
              "rb_hcr_file_changed", "rb_hcr_type_changed",
              "rb_hcr_register_managed_type"]:
    if not nmOut.contains(sym):
      fail("the target does not reference " & sym & " as an undefined " &
           "symbol, so it was built against the no-op fallback and every " &
           "assertion below would be about a process no agent can reach")
  let lddOut = execCmdEx("ldd " & quoteShell(result)).output
  if not lddOut.contains(agentLibName()):
    fail("the target records no dependency on " & agentLibName() & ":\n" &
         lddOut)

proc buildOversizePatchObject(): string =
  ## The step-38 body, compiled from REPROBUILD's own fixture rather than a
  ## copy here: both halves of step 38 are then provoked by the same bytes,
  ## and there is no second oversize fixture to drift.
  result = buildRoot / "oversize.o"
  let src = reproRoot / "tests" / "e2e" / "hcr-linux-rbhcr" / "hcr_lx_m8_patch.c"
  if not fileExists(src):
    fail("reprobuild's oversize patch fixture is missing at " & src)
  createDir(parentDir(result))
  discard runOrFail(["gcc", "-c", "-O2", "-fcf-protection=full",
                     "-ffunction-sections", src, "-o", result], repoRoot)

# ---------------------------------------------------------------------------
# The "developer edit" and its recompile
# ---------------------------------------------------------------------------

proc editedHotHeader(workDir: string; version: int): string =
  ## Copy the SHIPPED fixture and change its one integer literal.
  ##
  ## The edit is applied to a COPY on purpose: a harness killed between a
  ## mutation and its restore leaves the subject mutated, and `finally` is not
  ## a signal handler. What makes the copy honest rather than a different
  ## subject is asserted here — the bytes are read from the tracked file, and
  ## the rewrite is required to change EXACTLY one line.
  createDir(workDir)
  result = workDir / "nhm4_hot_header.nim"
  let original = readFile(hotHeaderPath)
  var outLines: seq[string] = @[]
  var edits = 0
  for line in original.splitLines():
    if line.strip() == "1" and line.len > line.strip().len:
      outLines.add(line[0 ..< line.len - 1] & $version)
      inc edits
    else:
      outLines.add(line)
  if edits != 1:
    fail("the developer edit changed " & $edits & " lines of " &
         hotHeaderPath & ", expected exactly 1. The fixture's editable " &
         "literal has moved; fix the fixture or this rewrite, but do not " &
         "let a zero-edit 'edit' compile to the same bytes and read green.")
  writeFile(result, outLines.join("\n") & "\n")
  if version != 1 and readFile(result) == original:
    fail("the edited copy is byte-identical to " & hotHeaderPath)

proc compilePatchObject(srcPath, nimcacheDir: string): string =
  ## Recompile the edited module ALONE and hand back the relocatable object
  ## holding the new body. `--noLinking` is what makes Nim run the C compiler
  ## and stop, which is the "Reprobuild recompiles the changed translation
  ## unit" step of `Patch-Loading-Lifecycle.md` Phase A.
  removeDir(nimcacheDir)
  discard runOrFail(["nim", "c", "--hints:off", "--warnings:off",
                     "--noLinking:on", "--nimcache:" & nimcacheDir,
                     "--stackTrace:off", "--lineTrace:off", "--checks:off",
                     "--opt:speed", "--passC:-fcf-protection=full",
                     srcPath], repoRoot)
  # Locate the object by what it DEFINES rather than by guessing Nim's
  # mangled cache filename, which is an encoding detail of the compiler.
  var found: seq[string] = @[]
  for kind, path in walkDir(nimcacheDir):
    if kind == pcFile and path.endsWith(".o"):
      if execCmdEx("nm --defined-only " & quoteShell(path)).output
          .contains(TargetSymbol):
        found.add path
  if found.len != 1:
    fail("expected exactly one object in " & nimcacheDir & " defining " &
         TargetSymbol & ", found " & $found.len & ". Nim's cache layout " &
         "changed, or the fixture stopped exporting the symbol.")
  found[0]

# ---------------------------------------------------------------------------
# Running one reload cycle
# ---------------------------------------------------------------------------

type
  ArmResult = object
    target: JsonNode
    targetLog: string
    targetExit: int
    driverLog: string
    driverExit: int
    sessionResults: seq[JsonNode]

proc shortSocketDir(tag: string): string =
  ## Deliberately NOT under the repo's `build/`: a workspace checked out below
  ## a long path blows `sun_path` and the failure surfaces from inside the
  ## driver as "socket path too long", naming nothing.
  result = getTempDir() / ("nhm4-" & tag & "-" & $getCurrentProcessId())
  createDir(result)
  if (result / "s").len > MaxUnixSocketPath:
    fail("the agent socket path would be " & $((result / "s").len) &
         " bytes, over the " & $MaxUnixSocketPath & "-byte budget " &
         "(sockaddr_un.sun_path is 108). Set TMPDIR to something short.")

proc readTargetJson(path: string; expectSchema = true): JsonNode =
  if not fileExists(path):
    return nil
  result = parseJson(readFile(path))
  if expectSchema and result["schemaId"].getStr() != SchemaId:
    fail("the target printed schemaId " & result["schemaId"].getStr() &
         ", expected " & SchemaId)

proc entryExists(path: string): bool =
  ## `os.fileExists` answers FALSE for a Unix socket — it is `stat` plus
  ## `S_ISREG`, and a socket is not a regular file. Measured while writing this
  ## gate: the "wait until the coordinator is listening" loop below spun its
  ## whole budget against a socket that had existed since the first iteration,
  ## and the arm then failed with a message about a socket that was plainly
  ## there. This asks the DIRECTORY, which answers for any file type.
  let parent = parentDir(path)
  if not dirExists(parent): return false
  for _, p in walkDir(parent):
    if p == path: return true
  false

proc spawnLogged(exe: string; args: openArray[string]; logPath: string;
                 extraEnv: openArray[(string, string)] = []): Process =
  ## Spawn with stdout+stderr redirected to a FILE by the shell rather than
  ## into a pipe this process reads only after the child exits.
  ##
  ## The pipe form deadlocks by construction here: the coordinator and the
  ## target run CONCURRENTLY and each writes diagnostics while the other is
  ## still being waited on, so whichever fills its 64 KiB pipe first blocks
  ## forever — and a coordinator blocked before it publishes its patch looks
  ## exactly like a target that was never patched.
  var env = newStringTable()
  for k, v in envPairs(): env[k] = v
  for (k, v) in extraEnv: env[k] = v
  var line = quoteShell(exe)
  for a in args: line.add " " & quoteShell(a)
  line.add " > " & quoteShell(logPath) & " 2>&1"
  startProcess("/bin/sh", workingDir = repoRoot, args = ["-c", line],
               env = env, options = {})

proc startTarget(targetBin, socketPath, markerPath, jsonPath, logPath: string;
                 reloads: int; pollBudget = 30000): Process =
  spawnLogged(targetBin,
              ["--marker=" & markerPath, "--json-out=" & jsonPath,
               "--reloads=" & $reloads, "--poll-budget=" & $pollBudget],
              logPath, [("REPRO_HCR_AGENT_SOCKET", socketPath)])

proc awaitListening(sockDirTag, socketPath: string; driver: Process;
                    driverLog: string) =
  ## The in-target agent dials OUT once, with a bounded retry and no later
  ## attempt, so the coordinator must be listening before the target starts.
  var waited = 0
  while not entryExists(socketPath) and waited < 20000:
    sleep(5); waited += 5
  if not entryExists(socketPath):
    driver.terminate(); discard driver.waitForExit(); driver.close()
    fail("the coordinator never began listening on " & socketPath &
         " within " & $waited & " ms (arm " & sockDirTag & "). Its log:\n" &
         (if fileExists(driverLog): readFile(driverLog) else: "<no log>"))

proc runOneShotArm(targetBin, driverBin, patchObject, patchSymbol,
                   patchId, tag: string): ArmResult =
  let sockDir = shortSocketDir(tag)
  defer: removeDir(sockDir)
  let armDir = buildRoot / "arms" / tag
  removeDir(armDir)
  createDir(armDir)
  let socketPath = sockDir / "s"
  let markerPath = armDir / "marker"
  let targetJson = armDir / "target.json"
  let driverJson = armDir / "driver.json"

  let driverLog = armDir / "driver.log"
  let targetLog = armDir / "target.log"
  let driver = spawnLogged(driverBin,
    ["--socket", socketPath, "--target-symbol", TargetSymbol,
     "--patch-object", patchObject, "--patch-symbol", patchSymbol,
     "--patch-id", patchId,
     "--changed-file", ChangedFile,
     "--changed-type", ManagedTypeSpec,
     "--wait-for", markerPath, "--marker", "nhm4-ready",
     "--marker-timeout-ms", "60000",
     "--json-out", driverJson], driverLog)
  awaitListening(tag, socketPath, driver, driverLog)

  let target = startTarget(targetBin, socketPath, markerPath, targetJson,
                           targetLog, 1)
  result.targetExit = target.waitForExit()
  target.close()
  result.driverExit = driver.waitForExit()
  driver.close()
  result.targetLog = (if fileExists(targetLog): readFile(targetLog) else: "")
  result.driverLog = (if fileExists(driverLog): readFile(driverLog) else: "")
  if result.targetExit != 0:
    # Loud, WITH BOTH LOGS. A bare `require arm.target != nil` three lines
    # later aborts the case with nothing to read, and the two processes that
    # know what went wrong have already written it down.
    fail("the target exited " & $result.targetExit & " in arm " & tag &
         ".\n--- target ---\n" & result.targetLog &
         "\n--- coordinator ---\n" & result.driverLog)
  result.target = readTargetJson(targetJson, true)

proc runSessionArm(targetBin, driverBin, tag: string;
                   requests: openArray[tuple[obj, sym, id: string]]): ArmResult =
  ## ONE connection, N patches — the live-edit loop the agent's GDH-M4 session
  ## loop exists for. A one-edit run cannot demonstrate it, which is why
  ## NH-M4's own text forbids closing the milestone on one.
  let sockDir = shortSocketDir(tag)
  defer: removeDir(sockDir)
  let armDir = buildRoot / "arms" / tag
  removeDir(armDir)
  createDir(armDir / "session")
  let socketPath = sockDir / "s"
  let sessionDir = armDir / "session"
  let markerPath = armDir / "marker"
  let targetJson = armDir / "target.json"

  let driverLog = armDir / "driver.log"
  let targetLog = armDir / "target.log"
  let driver = spawnLogged(driverBin,
    ["--socket", socketPath, "--target-symbol", TargetSymbol,
     "--session", "--session-dir", sessionDir,
     "--session-idle-timeout-ms", "120000",
     "--changed-file", ChangedFile,
     "--changed-type", ManagedTypeSpec,
     "--json-out", armDir / "driver.json"], driverLog)
  awaitListening(tag, socketPath, driver, driverLog)

  let target = startTarget(targetBin, socketPath, markerPath, targetJson,
                           targetLog, requests.len)

  proc awaitFile(path: string; budgetMs: int; what: string) =
    var w = 0
    while not fileExists(path) and w < budgetMs:
      sleep(10); w += 10
    if not fileExists(path):
      fail(what & " never appeared at " & path & " within " & $budgetMs &
           " ms. A session that stalls is not a session that refused; the " &
           "two must not be confused.")

  awaitFile(sessionDir / "ready", 60000, "the coordinator's session handshake")
  for i, req in requests:
    let n = i + 1
    let tmp = sessionDir / ("req-" & $n & ".json.tmp")
    writeFile(tmp, $(%*{"patchObject": req.obj, "patchSymbol": req.sym,
                        "patchId": req.id}))
    moveFile(tmp, sessionDir / ("req-" & $n & ".json"))
    awaitFile(sessionDir / ("res-" & $n & ".json"), 120000,
              "the verdict for edit " & $n)
    result.sessionResults.add parseJson(
      readFile(sessionDir / ("res-" & $n & ".json")))
  writeFile(sessionDir / "stop", "")

  result.targetExit = target.waitForExit()
  target.close()
  result.driverExit = driver.waitForExit()
  driver.close()
  result.targetLog = (if fileExists(targetLog): readFile(targetLog) else: "")
  result.driverLog = (if fileExists(driverLog): readFile(driverLog) else: "")
  if result.targetExit != 0:
    fail("the target exited " & $result.targetExit & " in session arm " &
         tag & ".\n--- target ---\n" & result.targetLog &
         "\n--- coordinator ---\n" & result.driverLog)
  result.target = readTargetJson(targetJson, true)

proc frameOf(node: JsonNode; key: string): string =
  decode(node[key].getStr())

# ---------------------------------------------------------------------------

requirePrerequisites()
createDir(buildRoot)

let started = epochTime()
let healthyLibDir = buildAgentLibrary(buildRoot / "agent-healthy")
let driverBin = buildDriver()
let targetBin = buildTarget(healthyLibDir, "nhm4_tui_target")
let oversizeObject = buildOversizePatchObject()

# The oversize body's SIZE is what makes the Phase F refusal real rather than
# a lever, so it is measured here instead of assumed.
block:
  let sizes = execCmdEx("nm --print-size --defined-only " &
                        quoteShell(oversizeObject)).output
  var oversizeBytes = 0
  for line in sizes.splitLines():
    if line.contains(OversizePatchSymbol):
      let parts = line.splitWhitespace()
      if parts.len >= 2: oversizeBytes = parseHexInt(parts[1])
  if oversizeBytes <= 4096:
    fail("the step-38 patch body is " & $oversizeBytes & " bytes; it must " &
         "exceed one page for repro_hcr_lx_txn_prepare_site to refuse it " &
         "inside Phase F. A smaller body would reach Phase G and the arm " &
         "would be testing a successful patch.")
  echo "[nhm4] oversize step-38 body: ", oversizeBytes, " bytes"

let editWork = buildRoot / "edits"
let patchV2 = compilePatchObject(editedHotHeader(editWork / "v2", 2),
                                 buildRoot / "nimcache" / "hot-v2")
let patchV3 = compilePatchObject(editedHotHeader(editWork / "v3", 3),
                                 buildRoot / "nimcache" / "hot-v3")
let patchV1 = compilePatchObject(editedHotHeader(editWork / "v1", 1),
                                 buildRoot / "nimcache" / "hot-v1")
echo "[nhm4] build + recompile took ",
     formatFloat(epochTime() - started, ffDecimal, 1), " s"

suite "NH-M4: IsoNim native HMR against the real Reprobuild agent":

  test "test_real_agent_tui_hmr_cycle":
    let t0 = epochTime()
    let arm = runOneShotArm(targetBin, driverBin, patchV2, TargetSymbol,
                            "nhm4-edit-1", "cycle")
    check arm.targetExit == 0
    check arm.driverExit == 0
    require arm.target != nil
    require arm.target["cycles"].len == 1
    let c = arm.target["cycles"][0]

    # --- the agent really ran the whole lifecycle, in the normative order ---
    check c["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,trampolines,after"
    check c["codeSwapped"].getBool()

    # --- the discriminating observation: the hooks OBSERVE THE VICTIM ------
    # Phase E cannot see the patch; Phase H must. A gate that counted
    # callbacks would be green under either ordering.
    check c["observedInBefore"]["fired"].getBool()
    check c["observedInAfter"]["fired"].getBool()
    check c["observedInBefore"]["version"].getInt() == 1
    check c["observedInAfter"]["version"].getInt() == 2

    # --- IsoNim's introspection surface, driven for real -------------------
    check c["observedInBefore"]["changedTypesCount"].getInt() == 1
    check c["observedInBefore"]["firstType"].getStr() == "isonim.UiSlot"
    check c["observedInBefore"]["firstTypeOldSize"].getInt() == 16
    check c["observedInBefore"]["firstTypeNewSize"].getInt() == 24
    check c["observedInAfter"]["fileChangedProbe"].getBool()
    check not c["observedInAfter"]["fileChangedAbsent"].getBool()

    # --- the entry re-ran and only the edited slot's hash moved ------------
    check arm.target["initialVersion"].getInt() == 1
    check c["slotHashHeader"].getStr() == "hdr2"
    check c["slotHashBody"].getStr() == "bdy1"
    check c["headerBuilds"].getInt() == 2
    check c["bodyBuilds"].getInt() == 1     # the untouched block never re-ran
    check c["appliedReloads"].getInt() == 1
    check c["failedReloads"].getInt() == 0
    check c["slotErrors"].getInt() == 0

    # --- the RECONCILER updated the live widget in place -------------------
    # One property changed and nothing was placed, moved, removed or
    # replaced. `touched == 1` is the operative form of "only the edited
    # widget was mutated".
    check c["reconcilePasses"].getInt() == 1
    let st = c["reconcileStats"]
    check st["propUpdates"].getInt() == 1
    check st["placed"].getInt() == 0
    check st["moved"].getInt() == 0
    check st["removed"].getInt() == 0
    check st["replaced"].getInt() == 0
    check st["touched"].getInt() == 1
    check st["matched"].getInt() > 0

    # --- nothing re-mounted; node identity survived ------------------------
    check c["rootNodeIsMountNode"].getBool()
    check c["rootNodeIsLiveRoot"].getBool()
    check c["uiHotMounts"].getInt() == arm.target["uiHotMountsBefore"].getInt() + 1
    check c["mountHandleStable"].getBool()
    check not c["mountDisposed"].getBool()
    check c["mountErrors"].getInt() == 0
    check c["headerNodeId"].getInt() ==
      arm.target["headerNodeIdAtMount"].getInt()
    check c["bodyNodeId"].getInt() == arm.target["bodyNodeIdAtMount"].getInt()

    # --- THE FRAME. Real cells, painted by the real compositor. ------------
    let before = arm.target.frameOf("initialFrame")
    let after = c.frameOf("frame")
    check before.contains("HEAD1-0")
    check before.contains("BODYSTABLE")
    check after != before
    check after.contains("HEAD2-3")          # new body, PRESERVED state (3)
    check not after.contains("HEAD1")
    check after.contains("BODYSTABLE")       # the rest is unchanged
    # The seam is installed and empty, so the wrappers fell THROUGH to the
    # real agent rather than to any hook.
    check not arm.target["hcrAgentHooksInstalled"].getBool()
    echo "[nhm4] cycle arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"

  test "test_control_real_agent_patch_that_changes_nothing_leaves_the_frame_identical":
    # The same binary, the same coordinator, the same wire — and a recompiled
    # body that returns the value it already returned. The patch IS applied
    # (`codeSwapped`, full trace), so this separates "a reload ran" from "a
    # changed ui block reached the surface". Without it, the arm above would
    # be satisfied by any repaint at all.
    let t0 = epochTime()
    let arm = runOneShotArm(targetBin, driverBin, patchV1, TargetSymbol,
                            "nhm4-noop-edit", "control-noop")
    check arm.targetExit == 0
    require arm.target != nil
    require arm.target["cycles"].len == 1
    let c = arm.target["cycles"][0]
    check c["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,trampolines,after"
    check c["codeSwapped"].getBool()         # code REALLY was swapped
    check c["observedInBefore"]["version"].getInt() == 1
    check c["observedInAfter"]["version"].getInt() == 1   # …to the same value
    check c["appliedReloads"].getInt() == 1               # the reload applied
    # …and nothing moved.
    check c["slotHashHeader"].getStr() == "hdr1"
    check c["headerBuilds"].getInt() == 1
    check c["bodyBuilds"].getInt() == 1
    check c["reconcilePasses"].getInt() == 0
    check c.frameOf("frame") == arm.target.frameOf("initialFrame")
    echo "[nhm4] no-op control arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"

  test "test_real_agent_tui_multi_edit_session":
    # The DEVELOPER EDIT LOOP. Reprobuild GDH-M4 gave the in-target agent a
    # session loop, so a process is no longer limited to one patch for its
    # lifetime — the constraint recorded at the top of
    # Hot-Module-Reload-Native.milestones.org on 2026-09-10. Two edits, one
    # connection, and each one observed independently.
    let t0 = epochTime()
    let arm = runSessionArm(targetBin, driverBin, "session", [
      (patchV2, TargetSymbol, "nhm4-session-edit-1"),
      (patchV3, TargetSymbol, "nhm4-session-edit-2")])
    check arm.targetExit == 0
    check arm.driverExit == 0
    check arm.sessionResults.len == 2
    for r in arm.sessionResults:
      check r["outcome"].getStr() == "applied"
    require arm.target != nil
    require arm.target["cycles"].len == 2

    let c1 = arm.target["cycles"][0]
    let c2 = arm.target["cycles"][1]
    # Each edit's before-hook sees the PREVIOUS body and its after-hook the
    # new one — the phase-order observation, repeated, on one connection.
    check c1["observedInBefore"]["version"].getInt() == 1
    check c1["observedInAfter"]["version"].getInt() == 2
    check c2["observedInBefore"]["version"].getInt() == 2
    check c2["observedInAfter"]["version"].getInt() == 3
    check c1["slotHashHeader"].getStr() == "hdr2"
    check c2["slotHashHeader"].getStr() == "hdr3"
    check c1["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,trampolines,after"
    check c2["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,trampolines,after"
    check c2["appliedReloads"].getInt() == 2
    check c2["failedReloads"].getInt() == 0
    # Two reconciler passes, each touching exactly one property, and the
    # untouched block never rebuilt across either edit.
    check c2["reconcilePasses"].getInt() == 2
    check c2["reconcileStats"]["touched"].getInt() == 1
    check c2["bodyBuilds"].getInt() == 1
    check c2["uiHotMounts"].getInt() == c1["uiHotMounts"].getInt()
    check c2["headerNodeId"].getInt() == c1["headerNodeId"].getInt()

    let f0 = arm.target.frameOf("initialFrame")
    let f1 = c1.frameOf("frame")
    let f2 = c2.frameOf("frame")
    check f0.contains("HEAD1-0")
    check f1.contains("HEAD2-3")
    check f2.contains("HEAD3-3")
    check f0 != f1
    check f1 != f2
    for f in [f0, f1, f2]:
      check f.contains("BODYSTABLE")
    echo "[nhm4] multi-edit session arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"

  test "test_real_agent_step38_late_load_failure_cycle":
    # `Patch-Loading-Lifecycle.md` §3.3 step 38, against the REAL agent for
    # the first time. The load fails at Phase F after before-reload has
    # already fired; the agent must still invoke after-reload with zero
    # `changed_types`, must mark nothing applied, and must roll back the
    # introspection window it latched before Phase E.
    #
    # IsoNim is correct here WITHOUT DETECTING IT (design doc, "Failure
    # mode"): the entry re-runs against bodies that were never replaced,
    # re-registers the hash already in the registry, `applyRegistration`
    # takes its equality branch, and nothing on the surface moves.
    let t0 = epochTime()
    let arm = runSessionArm(targetBin, driverBin, "step38", [
      (oversizeObject, OversizePatchSymbol, "nhm4-step38"),
      (patchV2, TargetSymbol, "nhm4-step38-recovery")])
    check arm.targetExit == 0
    check arm.sessionResults.len == 2
    check arm.sessionResults[0]["outcome"].getStr() == "refused"
    check arm.sessionResults[1]["outcome"].getStr() == "applied"
    require arm.target != nil
    require arm.target["cycles"].len == 2
    let failed = arm.target["cycles"][0]
    let recovered = arm.target["cycles"][1]

    # --- the agent's half of step 38 ---------------------------------------
    check failed["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,load-failed,after"
    check not failed["codeSwapped"].getBool()
    check failed["beforeReloads"].getInt() == 1
    check failed["afterReloads"].getInt() == 1     # after STILL fired
    check failed["observedInBefore"]["changedTypesCount"].getInt() == 1
    check failed["observedInAfter"]["changedTypesCount"].getInt() == 0

    # ONE predicate observed FLIPPING inside ONE run. `rb_hcr_file_changed`
    # is true inside the before-callback (the window latched on the accepted
    # patch) and false inside the after-callback, because the failed load
    # un-latched it. No always-true and no always-false implementation can
    # produce that, and it is read through IsoNim's own wrapper.
    check failed["observedInBefore"]["fileChangedProbe"].getBool()
    check not failed["observedInAfter"]["fileChangedProbe"].getBool()
    check not failed["fileChangedAtEnd"].getBool()

    # --- IsoNim's half: the surface never moved ----------------------------
    check failed.frameOf("frame") == arm.target.frameOf("initialFrame")
    check failed["slotHashHeader"].getStr() == "hdr1"
    check failed["headerBuilds"].getInt() == 1
    check failed["bodyBuilds"].getInt() == 1
    check failed["reconcilePasses"].getInt() == 0
    check failed["renders"].getInt() == 1
    check failed["rootNodeIsMountNode"].getBool()
    check failed["mountErrors"].getInt() == 0
    check failed["slotErrors"].getInt() == 0
    # Recorded rather than asserted-away: IsoNim counts this as an APPLIED
    # reload, because its entry call did not raise. That is the design's
    # "correct on that path without detecting it" made visible — zero
    # `changed_types` is also what an ordinary no-layout-change patch
    # carries, so it is not a discriminator the application could branch on
    # (OPEN-5).
    check failed["appliedReloads"].getInt() == 1
    check failed["failedReloads"].getInt() == 0

    # --- the RECOVERY control: the process is not wedged -------------------
    # Without this, "nothing moved" would be what this instrument says about
    # every run of this binary.
    check recovered["lifecycleTrace"].getStr() ==
      "prepare,latch,before,load,trampolines,after"
    check recovered["codeSwapped"].getBool()
    check recovered["observedInAfter"]["version"].getInt() == 2
    check recovered["observedInAfter"]["changedTypesCount"].getInt() == 1
    check recovered["observedInAfter"]["fileChangedProbe"].getBool()
    check recovered["slotHashHeader"].getStr() == "hdr2"
    check recovered["reconcilePasses"].getInt() == 1
    check recovered.frameOf("frame") != arm.target.frameOf("initialFrame")
    check recovered.frameOf("frame").contains("HEAD2-3")
    echo "[nhm4] step-38 arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"

  test "test_falsifier_inverted_phase_order_breaks_the_cycle":
    # The SAME arm-1 run against an agent with exactly one property removed:
    # `-DREPRO_HCR_FALSIFY_BEFORE_RELOAD_AFTER_SWAP` fires before-reload AFTER
    # Phase G — the ordering IsoNim's design doc asked for until 2026-09-17
    # and `Patch-Loading-Lifecycle.md` §3.1 forbids.
    #
    # This is what makes arm 1's `observedInBefore.version == 1` a
    # measurement. Under this agent the before-hook reads the POST-swap value
    # and the trace puts `before` after `trampolines`, so that assertion —
    # and only that class of assertion — goes red.
    let t0 = epochTime()
    let libDir = buildAgentLibrary(buildRoot / "agent-falsify-order",
                                   [FalsifyPhaseOrder])
    let bin = buildTarget(libDir, "nhm4_tui_target_falsify_order")
    let arm = runOneShotArm(bin, driverBin, patchV2, TargetSymbol,
                            "nhm4-falsify-order", "falsify-order")
    check arm.targetExit == 0
    require arm.target != nil
    require arm.target["cycles"].len == 1
    let c = arm.target["cycles"][0]
    check c["lifecycleTrace"].getStr() ==
      "prepare,latch,load,trampolines,before,after"
    # THE KILL: arm 1 asserts 1 here.
    check c["observedInBefore"]["version"].getInt() == 2
    check c["observedInAfter"]["version"].getInt() == 2
    echo "[nhm4] inverted-order falsifier arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"

  test "test_falsifier_skipped_step38_never_reaches_after_reload":
    # Arm 4's obligation, removed: `-DREPRO_HCR_FALSIFY_SKIP_STEP38` drops the
    # after-reload dispatch on a Phase F failure. IsoNim's target then never
    # observes a reload cycle for the failed load and exits 3 with its own
    # named reason — which is arm 4's `afterReloads == 1` measured going red,
    # and is also the proof that the target refuses to report a cycle it did
    # not see.
    let t0 = epochTime()
    let libDir = buildAgentLibrary(buildRoot / "agent-falsify-step38",
                                   [FalsifySkipStep38])
    let bin = buildTarget(libDir, "nhm4_tui_target_falsify_step38")
    let sockDir = shortSocketDir("falsify-step38")
    defer: removeDir(sockDir)
    let armDir = buildRoot / "arms" / "falsify-step38"
    removeDir(armDir); createDir(armDir)
    let socketPath = sockDir / "s"
    let driverLog = armDir / "driver.log"
    let driver = spawnLogged(driverBin,
      ["--socket", socketPath, "--target-symbol", TargetSymbol,
       "--patch-object", oversizeObject,
       "--patch-symbol", OversizePatchSymbol,
       "--patch-id", "nhm4-falsify-step38",
       "--changed-file", ChangedFile,
       "--changed-type", ManagedTypeSpec,
       "--wait-for", armDir / "marker", "--marker", "nhm4-ready",
       "--marker-timeout-ms", "60000",
       "--json-out", armDir / "driver.json"], driverLog)
    awaitListening("falsify-step38", socketPath, driver, driverLog)
    # A short budget: the target polls 1 ms apart, so 6000 polls is ~6 s and
    # the arm does not pay the full 30 s default to learn what it already
    # knows. It is still an order of magnitude above the ~40 ms the healthy
    # arms take to observe their cycle, measured.
    let target = startTarget(bin, socketPath, armDir / "marker",
                             armDir / "target.json", armDir / "target.log",
                             1, pollBudget = 6000)
    let exitCode = target.waitForExit()
    target.close()
    discard driver.waitForExit()
    driver.close()
    let log = (if fileExists(armDir / "target.log"):
                 readFile(armDir / "target.log") else: "")
    check exitCode == 3
    check log.contains("reload cycles were observed")
    check not fileExists(armDir / "target.json")
    echo "[nhm4] skipped-step38 falsifier arm: ",
         formatFloat(epochTime() - t0, ffDecimal, 1), " s"
