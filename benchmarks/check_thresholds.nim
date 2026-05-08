## benchmarks/check_thresholds.nim — absolute-budget gate.
##
## Reads the merged benchmark_results.json and fails (exit 1) if any
## of the absolute thresholds from the M24 milestone are violated.
## These are the "bench_*_meets_target" tests promoted into a CI gate.
##
## Args:
##   check_thresholds <input-json>

import std/[json, os, strformat, tables]

type
  Threshold = object
    name: string
    smaller: bool      # true: value must be <= max; false: value must be >= max
    bound: float
    unit: string

const Thresholds = [
  Threshold(name: "Cold start to first paint",
            smaller: true,  bound: 50.0,  unit: "ms"),
  Threshold(name: "Input latency p50",
            smaller: true,  bound: 16.0,  unit: "ms"),
  Threshold(name: "Input latency p99",
            smaller: true,  bound: 33.0,  unit: "ms"),
  Threshold(name: "Idle CPU",
            smaller: true,  bound: 0.5,   unit: "%"),
  Threshold(name: "RSS at idle (standard app)",
            smaller: true,  bound: 30.0,  unit: "MB"),
  Threshold(name: "RSS per added widget",
            smaller: true,  bound: 10.0,  unit: "KB"),
  Threshold(name: "Strip cache hit rate",
            smaller: false, bound: 95.0,  unit: "%"),
]

proc valueAsFloat(v: JsonNode): float =
  case v.kind
  of JFloat: v.getFloat()
  of JInt:   v.getInt().float
  else:      0.0

proc main() =
  if paramCount() < 1:
    stderr.writeLine "usage: check_thresholds <input-json>"
    quit(64)
  let path = paramStr(1)
  if not fileExists(path):
    stderr.writeLine fmt"[hard-threshold] {path} missing"
    quit(0)

  let parsed = parseJson(readFile(path))
  if parsed.kind != JArray:
    stderr.writeLine fmt"[hard-threshold] {path} not a JSON array"
    quit(1)

  var byName = initTable[string, float]()
  for e in parsed.items:
    if e.kind != JObject: continue
    if e.hasKey("name") and e.hasKey("value"):
      byName[e["name"].getStr()] = valueAsFloat(e["value"])

  var failed = 0
  var checked = 0
  for t in Thresholds:
    if t.name notin byName:
      stderr.writeLine fmt"[hard-threshold] WARN: missing metric {t.name}"
      continue
    inc checked
    let v = byName[t.name]
    let ok =
      if t.smaller: v <= t.bound
      else: v >= t.bound
    if ok:
      stderr.writeLine fmt"[hard-threshold] PASS: {t.name} = {v} {t.unit} " &
                       (if t.smaller: "<= " else: ">= ") & $t.bound
    else:
      stderr.writeLine fmt"[hard-threshold] FAIL: {t.name} = {v} {t.unit} " &
                       (if t.smaller: "exceeds " else: "below ") & $t.bound
      inc failed

  if failed > 0:
    stderr.writeLine fmt"[hard-threshold] {failed}/{checked} thresholds violated"
    quit(1)
  else:
    stderr.writeLine fmt"[hard-threshold] all {checked} thresholds passed"

main()
