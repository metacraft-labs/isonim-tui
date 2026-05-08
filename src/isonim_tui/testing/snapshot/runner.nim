## Snapshot runner.
##
## `snap(name, ...)` records or compares all six formats. First run
## with no goldens records; subsequent runs compare and write a per-run
## HTML report when any format mismatches. Setting `SNAP_RECORD=1` in
## the environment forces a re-record (or pass `recordMode = true`
## explicitly).
##
## Goldens land under `tests/snapshots/<name>/` — one file per format:
##   plaintext.txt, ansi.ansi, cellmap.json, svg.svg,
##   annotated.svg, treedump.txt.
##
## On failure the runner emits `tests/snapshots/_report.html` with the
## golden / actual / diff for each format that mismatched. Each test
## that mismatches appends to the report so a CI run accumulates all
## failures in one artifact.

import std/[os, strutils, times]

import ../../cells
import ../../renderer
import ../../compositor
import ./plaintext
import ./ansi as ansiSnap
import ./cellmap
import ./svg
import ./annotated_svg
import ./treedump

type
  SnapshotResult* = object
    name*: string
    format*: string
    matched*: bool
    golden*: string
    actual*: string

  SnapshotReport* = object
    results*: seq[SnapshotResult]

proc snapshotsDir(): string =
  ## Resolve `tests/snapshots/`. In practice tests run from the repo
  ## root or from `tests/`; we walk up to find the `tests` directory.
  let cwd = getCurrentDir()
  if dirExists(cwd / "tests" / "snapshots"):
    return cwd / "tests" / "snapshots"
  if dirExists(cwd / "snapshots"):
    return cwd / "snapshots"
  # Fallback: env override.
  let env = getEnv("ISONIM_TUI_SNAPSHOT_DIR")
  if env.len > 0:
    return env
  return cwd / "tests" / "snapshots"

proc isRecordMode*(): bool =
  getEnv("SNAP_RECORD", "") != ""

proc readIfExists(path: string): string =
  if fileExists(path):
    return readFile(path)
  return ""

proc writeAtomic(path: string; contents: string) =
  createDir(path.parentDir)
  writeFile(path, contents)

type
  SnapInputs* = object
    ## Input bundle for a single `snap()` call. The harness gathers
    ## these and passes them through.
    name*: string
    buffer*: ScreenBuffer
    root*: TerminalNode
    compositor*: Compositor
    focusedId*: int

proc encodeAll(s: SnapInputs): seq[(string, string)] =
  ## Returns (filename, contents) pairs in canonical order.
  result = @[]
  result.add ("plaintext.txt", encodePlaintext(s.buffer))
  result.add ("ansi.ansi", ansiSnap.encodeAnsi(s.buffer))
  result.add ("cellmap.json", encodeCellMap(s.buffer))
  result.add ("svg.svg", encodeSvg(s.buffer))
  result.add ("annotated.svg",
              encodeAnnotatedSvg(s.buffer, s.root, s.compositor, s.focusedId))
  result.add ("treedump.txt", encodeTreeDump(s.compositor, s.root))

# A thread-local report accumulator. Tests that run in sequence on the
# same thread share the same report; the harness clears it on dispose.
var snapshotAccumulator* {.threadvar.}: SnapshotReport

proc resetSnapshotAccumulator*() =
  snapshotAccumulator = SnapshotReport(results: @[])

proc lineDiff(golden, actual: string): string =
  ## Cheap line-by-line diff. Marks added/removed lines with +/- so
  ## the HTML report reads sensibly.
  let gl = golden.splitLines()
  let al = actual.splitLines()
  let n = max(gl.len, al.len)
  var diffLines: seq[string] = @[]
  for i in 0 ..< n:
    let g = if i < gl.len: gl[i] else: ""
    let a = if i < al.len: al[i] else: ""
    if g == a:
      diffLines.add "  " & g
    else:
      if g.len > 0: diffLines.add "- " & g
      if a.len > 0: diffLines.add "+ " & a
  diffLines.join("\n")

proc writeHtmlReport*(report: SnapshotReport; reportPath: string) =
  if report.results.len == 0: return
  var html: seq[string] = @[]
  html.add "<!DOCTYPE html>"
  html.add "<html><head><meta charset=\"utf-8\">"
  html.add "<title>isonim-tui snapshot report</title>"
  html.add "<style>"
  html.add "body{font-family:monospace;padding:1em;}"
  html.add ".case{margin-bottom:2em;border:1px solid #ccc;padding:1em;}"
  html.add ".case.fail{border-color:#c33;background:#fff5f5;}"
  html.add ".case.pass{border-color:#3c3;background:#f5fff5;}"
  html.add ".cols{display:flex;gap:1em;}"
  html.add ".col{flex:1;}"
  html.add "pre{background:#f0f0f0;padding:0.5em;overflow:auto;max-height:300px;}"
  html.add "</style></head><body>"
  html.add "<h1>Snapshot report — " & $now() & "</h1>"
  for r in report.results:
    let cls = if r.matched: "pass" else: "fail"
    html.add "<div class=\"case " & cls & "\">"
    html.add "<h2>" & r.name & " / " & r.format & " — " &
             (if r.matched: "PASS" else: "FAIL") & "</h2>"
    if not r.matched:
      html.add "<div class=\"cols\">"
      html.add "<div class=\"col\"><h3>Golden</h3><pre>" &
               r.golden.multiReplace(("<", "&lt;"), (">", "&gt;")) &
               "</pre></div>"
      html.add "<div class=\"col\"><h3>Actual</h3><pre>" &
               r.actual.multiReplace(("<", "&lt;"), (">", "&gt;")) &
               "</pre></div>"
      html.add "<div class=\"col\"><h3>Diff</h3><pre>" &
               lineDiff(r.golden, r.actual)
                 .multiReplace(("<", "&lt;"), (">", "&gt;")) &
               "</pre></div>"
      html.add "</div>"
    html.add "</div>"
  html.add "</body></html>"
  writeAtomic(reportPath, html.join("\n"))

proc snapImpl*(s: SnapInputs; recordMode: bool = false): bool =
  ## Internal: record (force-write goldens) or compare. Returns true on
  ## match (or always true when recording). The snapshot accumulator is
  ## updated; the caller is responsible for emitting the HTML report.
  let baseDir = snapshotsDir() / s.name
  let formats = encodeAll(s)
  let effectiveRecord = recordMode or isRecordMode()
  var allMatched = true
  for (fname, contents) in formats:
    let path = baseDir / fname
    if effectiveRecord or not fileExists(path):
      writeAtomic(path, contents)
      snapshotAccumulator.results.add SnapshotResult(
        name: s.name, format: fname, matched: true,
        golden: contents, actual: contents)
      continue
    let golden = readIfExists(path)
    let matched = golden == contents
    if not matched: allMatched = false
    snapshotAccumulator.results.add SnapshotResult(
      name: s.name, format: fname, matched: matched,
      golden: golden, actual: contents)
  if not allMatched:
    let reportPath = snapshotsDir() / "_report.html"
    writeHtmlReport(snapshotAccumulator, reportPath)
    # Echo a summary so test stdout has the diff readable inline.
    echo "[snapshot] mismatch on `", s.name, "` — see ", reportPath
    for r in snapshotAccumulator.results:
      if r.name == s.name and not r.matched:
        echo "  format ", r.format, " differs"
  return allMatched
