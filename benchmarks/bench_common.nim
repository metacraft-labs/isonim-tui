## benchmarks/bench_common.nim — shared utilities for M24 benchmarks.
##
## Each benchmark writes one or more JSON entries to
## `bench-results/<name>.json` in a tiny array fragment. The aggregator
## (`scripts/collect-benchmark-metrics.sh`) reads every fragment and
## merges them into the single `bench-results/benchmark_results.json`.
##
## Format per github-action-benchmark v1:
##
##   {"name": "...", "unit": "ms", "value": 12.3, "extra": "..."}
##
## A `BenchEntry` value object captures one metric. `writeBenchFragment`
## serialises a seq into a JSON array file.

import std/[algorithm, json, os, strutils, monotimes, times]

type
  BenchEntry* = object
    name*: string
    unit*: string
    value*: float
    extra*: string

  BenchOptions* = object
    quick*: bool
    outputDir*: string
    fragmentName*: string

proc parseBenchOptions*(): BenchOptions =
  ## Parse `--quick` and `--output-dir=<path>` from `paramStr/Count`.
  ## A benchmark binary calls this at startup; defaults match the
  ## standard layout.
  result = BenchOptions(quick: false,
                        outputDir: "bench-results",
                        fragmentName: "")
  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--quick":
      result.quick = true
    elif arg.startsWith("--output-dir="):
      result.outputDir = arg["--output-dir=".len .. ^1]
    elif arg.startsWith("--fragment="):
      result.fragmentName = arg["--fragment=".len .. ^1]

proc toJsonNode*(e: BenchEntry): JsonNode =
  result = %*{
    "name": e.name,
    "unit": e.unit,
    "value": e.value
  }
  if e.extra.len > 0:
    result["extra"] = %e.extra

proc writeBenchFragment*(opts: BenchOptions; entries: openArray[BenchEntry]) =
  ## Serialise `entries` as a JSON array under
  ## `<outputDir>/<fragmentName>.json`. Creates the directory if needed.
  if not dirExists(opts.outputDir):
    createDir(opts.outputDir)
  let fragName =
    if opts.fragmentName.len > 0: opts.fragmentName
    else: extractFilename(getAppFilename())
  let fragPath = opts.outputDir / (fragName & ".json")
  var arr = newJArray()
  for e in entries:
    arr.add toJsonNode(e)
  writeFile(fragPath, $arr & "\n")
  stderr.writeLine "[bench:" & fragName & "] wrote " & $entries.len &
                   " entries to " & fragPath

proc nowMs*(): float =
  ## Current monotonic time in milliseconds (float, sub-millisecond
  ## precision). Used for cheap inline timings inside a benchmark.
  let t = getMonoTime()
  inMicroseconds(t - MonoTime()).float / 1000.0

proc elapsedMs*(start: MonoTime): float =
  let now = getMonoTime()
  inMicroseconds(now - start).float / 1000.0

proc nowMonoMs*(): MonoTime {.inline.} = getMonoTime()

proc percentile*(samples: openArray[float]; p: float): float =
  ## p in [0, 1]. Returns the linear-interpolated percentile of
  ## `samples` (which is sorted in-place via a copy).
  if samples.len == 0: return 0.0
  var s = newSeq[float](samples.len)
  for i, v in samples: s[i] = v
  s.sort()
  let idx = (p * float(s.len - 1))
  let lo = int(idx)
  let hi = min(lo + 1, s.len - 1)
  let frac = idx - float(lo)
  s[lo] * (1.0 - frac) + s[hi] * frac

proc median*(samples: openArray[float]): float =
  percentile(samples, 0.5)

proc mean*(samples: openArray[float]): float =
  if samples.len == 0: return 0.0
  var s = 0.0
  for v in samples: s += v
  s / float(samples.len)

proc cpuJiffies*(pid: int = 0): tuple[utime, stime: int64] =
  ## Read /proc/<pid>/stat utime+stime (Linux). Returns (0, 0) on other
  ## platforms. PID 0 means "self".
  when defined(linux):
    let target =
      if pid == 0: "/proc/self/stat"
      else: "/proc/" & $pid & "/stat"
    if not fileExists(target): return (0'i64, 0'i64)
    let raw = readFile(target)
    # Format: <pid> (<comm>) <state> <ppid> ...
    # utime is field 14, stime is field 15 (1-indexed). Find the last ')'
    # before tokenising — comm may contain spaces.
    let lastClose = raw.rfind(')')
    if lastClose < 0: return (0'i64, 0'i64)
    let tail = raw[lastClose + 1 .. ^1].strip()
    let parts = tail.splitWhitespace()
    if parts.len < 13: return (0'i64, 0'i64)
    # state is parts[0]; ppid parts[1]; ... utime is parts[11], stime parts[12].
    try:
      let utime = parseBiggestInt(parts[11]).int64
      let stime = parseBiggestInt(parts[12]).int64
      return (utime, stime)
    except ValueError:
      return (0'i64, 0'i64)
  else:
    return (0'i64, 0'i64)

proc rssKb*(): int64 =
  ## Read /proc/self/statm (Linux) and return resident-set size in KB.
  ## Returns 0 on non-Linux platforms.
  when defined(linux):
    if not fileExists("/proc/self/statm"): return 0
    let raw = readFile("/proc/self/statm")
    let parts = raw.splitWhitespace()
    if parts.len < 2: return 0
    try:
      # statm fields are in pages. Page size is typically 4096.
      let resPages = parseBiggestInt(parts[1]).int64
      let pageKb = 4'i64
      return resPages * pageKb
    except ValueError:
      return 0
  else:
    return 0
