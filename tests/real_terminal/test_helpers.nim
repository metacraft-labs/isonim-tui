## Shared helpers for the M29 real-terminal test suite.
##
## Each test compiles a small `apps/<stem>.nim` child binary and spawns
## it under TermAssert inside a real pty. On failure the diagnostics
## helper writes a bundle (pty transcript + plaintext + SVG screen +
## the in-process snapshot from the M2 harness) to
## `test-logs/real-terminal/<test-name>/`.

import std/[os, osproc, times]

const
  binDir* = "test-logs/real-terminal"

proc realTerminalBinDir*(): string =
  ## Return an absolute path to the directory in which compiled
  ## test-app binaries live. Created on demand.
  let here = currentSourcePath().parentDir()
  let repoRoot = here.parentDir().parentDir()
  let dir = repoRoot / binDir / "bin"
  createDir(dir)
  dir

proc childAppPath*(stem: string): string =
  ## Path to the compiled binary for `apps/<stem>.nim`.
  realTerminalBinDir() / stem

proc compileApp*(stem: string) =
  ## Compile `tests/real_terminal/apps/<stem>.nim` if missing or stale.
  let here = currentSourcePath().parentDir()
  let src = here / "apps" / (stem & ".nim")
  if not fileExists(src):
    raise newException(IOError, "child app source missing: " & src)
  let outBin = childAppPath(stem)
  if fileExists(outBin):
    let outTime = getFileInfo(outBin).lastWriteTime
    let srcTime = getFileInfo(src).lastWriteTime
    let runtime = here / "apps" / "app_runtime.nim"
    let runtimeTime =
      if fileExists(runtime): getFileInfo(runtime).lastWriteTime
      else: srcTime
    let newest =
      if srcTime.toUnixFloat() > runtimeTime.toUnixFloat(): srcTime
      else: runtimeTime
    if outTime.toUnixFloat() > newest.toUnixFloat(): return
  let cmd = "nim c --styleCheck:usages --styleCheck:error --mm:orc -d:release --threads:on " &
            "-o:" & outBin & " " & src
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    raise newException(IOError,
      "failed to compile child app " & stem & ":\n" & output)

proc bundleDir*(testName: string): string =
  ## Return the diagnostics bundle directory for `testName`. Created on
  ## demand; safe to call multiple times.
  let here = currentSourcePath().parentDir()
  let repoRoot = here.parentDir().parentDir()
  let dir = repoRoot / binDir / testName
  createDir(dir)
  dir
