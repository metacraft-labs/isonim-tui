## benchmarks/merge_fragments.nim — combine per-benchmark JSON fragments
## into a single bench-results/benchmark_results.json.
##
## Invoked from `scripts/collect-benchmark-metrics.sh` after every
## benchmark binary has run.
##
## Args:
##   merge_fragments <output-dir> <name1> <name2> ...
##
## Reads `<output-dir>/<name>.json` for each name, treats each file as
## a JSON array of `{name, unit, value, extra}` entries, and writes the
## flat concatenation to `<output-dir>/benchmark_results.json`.

import std/[json, os, strformat]

proc main() =
  if paramCount() < 2:
    stderr.writeLine "usage: merge_fragments <output-dir> <name1> ..."
    quit(64)

  let outDir = paramStr(1)
  let outFile = outDir / "benchmark_results.json"

  var merged = newJArray()
  for i in 2 .. paramCount():
    let name = paramStr(i)
    let path = outDir / (name & ".json")
    if not fileExists(path):
      stderr.writeLine fmt"[merge] WARN: fragment missing: {path}"
      continue
    let raw =
      try: readFile(path)
      except IOError as e:
        stderr.writeLine fmt"[merge] WARN: read error {path}: {e.msg}"
        continue
    let parsed =
      try: parseJson(raw)
      except JsonParsingError as e:
        stderr.writeLine fmt"[merge] WARN: parse error in {path}: {e.msg}"
        continue
    if parsed.kind != JArray:
      stderr.writeLine fmt"[merge] WARN: {path} not a JSON array"
      continue
    for entry in parsed.items:
      if entry.kind != JObject:
        continue
      if not entry.hasKey("name") or not entry.hasKey("unit") or
         not entry.hasKey("value"):
        stderr.writeLine fmt"[merge] WARN: dropping malformed entry in {path}"
        continue
      merged.add entry

  writeFile(outFile, merged.pretty(2) & "\n")
  stderr.writeLine fmt"[merge] wrote {merged.len} entries to {outFile}"

main()
