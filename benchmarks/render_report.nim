## benchmarks/render_report.nim — produce bench-results/report.html.
##
## Reads the merged JSON file and emits a self-contained HTML report
## (inline CSS, no external <script src=> or <link href=> URLs).
##
## Args:
##   render_report <input-json> <output-html>
##                 [--baseline=PATH] [--sha=SHA] [--quick=full|quick]
##                 [--host=HOST] [--kernel=K] [--cpu=CPU] [--date=...]

import std/[json, os, strformat, strutils, times, tables]

type
  Meta = object
    sha: string
    quick: string
    host: string
    kernel: string
    cpu: string
    date: string

proc esc(s: string): string =
  ## Minimal HTML escaping for text + attribute contexts.
  for c in s:
    case c
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '&': result.add "&amp;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

proc fmtFloat(v: float): string =
  let av = abs(v)
  if av >= 1000.0: result = formatFloat(v, ffDecimal, 1)
  elif av >= 10.0: result = formatFloat(v, ffDecimal, 2)
  elif av >= 1.0:  result = formatFloat(v, ffDecimal, 3)
  else:            result = formatFloat(v, ffDecimal, 4)

proc fmtVal(v: JsonNode): string =
  case v.kind
  of JFloat: fmtFloat(v.getFloat())
  of JInt:   $v.getInt()
  else:      v.getStr()

proc valueAsFloat(v: JsonNode): float =
  case v.kind
  of JFloat: v.getFloat()
  of JInt:   v.getInt().float
  else:      0.0

const Categories = [
  ("Render",       @["Cold start", "Compositor", "Animation"]),
  ("Input",        @["Input latency", "Input parser"]),
  ("Layout/CSS",   @["CSS cascade"]),
  ("Scroll",       @["DataTable", "Strip cache"]),
  ("Memory",       @["RSS"]),
  ("Reactive",     @["Reactive"]),
  ("Snapshot",     @["Snapshot"]),
  ("vs. Textual",  @["vs. Textual"]),
  ("Other",        @["Idle"]),
]

proc categoryFor(name: string): string =
  for (cat, kws) in Categories:
    for kw in kws:
      if kw.toLowerAscii in name.toLowerAscii:
        return cat
  return "Other"

proc parseArg(a: string; key: string; dest: var string): bool =
  let prefix = key & "="
  if a.startsWith(prefix):
    dest = a[prefix.len .. ^1]
    return true
  return false

proc main() =
  if paramCount() < 2:
    stderr.writeLine "usage: render_report <input-json> <output-html> [opts]"
    quit(64)

  let inJson = paramStr(1)
  let outHtml = paramStr(2)
  var meta = Meta(quick: "full", date: $now())
  var baselinePath = ""

  for i in 3 .. paramCount():
    let a = paramStr(i)
    if parseArg(a, "--baseline", baselinePath): discard
    elif parseArg(a, "--sha", meta.sha): discard
    elif parseArg(a, "--quick", meta.quick): discard
    elif parseArg(a, "--host", meta.host): discard
    elif parseArg(a, "--kernel", meta.kernel): discard
    elif parseArg(a, "--cpu", meta.cpu): discard
    elif parseArg(a, "--date", meta.date): discard

  if not fileExists(inJson):
    stderr.writeLine fmt"[render] ERROR: missing {inJson}"
    quit(1)

  let metrics = parseJson(readFile(inJson))
  if metrics.kind != JArray:
    stderr.writeLine fmt"[render] ERROR: {inJson} not array"
    quit(1)

  var baseMap = initTable[string, JsonNode]()
  if baselinePath.len > 0 and fileExists(baselinePath):
    let baseline = parseJson(readFile(baselinePath))
    if baseline.kind == JArray:
      for e in baseline.items:
        if e.kind == JObject and e.hasKey("name"):
          baseMap[e["name"].getStr()] = e

  # Group by category in declaration order.
  var byCat = initOrderedTable[string, seq[JsonNode]]()
  for e in metrics.items:
    if e.kind != JObject: continue
    let nm =
      if e.hasKey("name"): e["name"].getStr()
      else: ""
    let cat = categoryFor(nm)
    if cat notin byCat:
      byCat[cat] = @[]
    byCat[cat].add e

  let hasBaseline = baseMap.len > 0
  let tableHead =
    if hasBaseline:
      "<tr><th>Metric</th><th>Value</th><th>Unit</th>" &
      "<th>Baseline</th><th>Delta / Notes</th></tr>"
    else:
      "<tr><th>Metric</th><th>Value</th><th>Unit</th>" &
      "<th colspan=\"2\">Notes</th></tr>"

  var rows = ""
  for cat, entries in byCat:
    rows.add fmt("""<tr class="cat-row"><th colspan="5">{esc(cat)}</th></tr>""")
    for m in entries:
      let nm = if m.hasKey("name"): m["name"].getStr() else: ""
      let unit = if m.hasKey("unit"): m["unit"].getStr() else: ""
      let extra = if m.hasKey("extra"): m["extra"].getStr() else: ""
      let valStr = if m.hasKey("value"): fmtVal(m["value"]) else: ""
      var baseCell = ""
      var deltaCell = ""
      if hasBaseline:
        if nm in baseMap:
          let b = baseMap[nm]
          if b.hasKey("value"):
            baseCell = fmtVal(b["value"])
            let bv = valueAsFloat(b["value"])
            let cv = if m.hasKey("value"): valueAsFloat(m["value"]) else: 0.0
            if bv != 0.0:
              let delta = (cv - bv) / bv * 100.0
              let cls = if delta > 0.0: "delta-up" else: "delta-down"
              deltaCell = fmt("""<span class="{cls}">{formatFloat(delta, ffDecimal, 1)}%</span>""")
      if hasBaseline:
        rows.add fmt("""<tr><td>{esc(nm)}</td><td>{valStr}</td><td>{esc(unit)}</td>""" &
                     """<td>{baseCell}</td><td>{deltaCell}<br><small>{esc(extra)}</small></td></tr>""")
      else:
        rows.add fmt("""<tr><td>{esc(nm)}</td><td>{valStr}</td><td>{esc(unit)}</td>""" &
                     """<td colspan="2"><small>{esc(extra)}</small></td></tr>""")

  let css = """
:root {
  --fg: #0f172a; --bg: #ffffff; --border: #e2e8f0;
  --muted: #64748b; --accent: #2563eb;
  --catbg: #f1f5f9;
}
body { margin: 0; padding: 0; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; color: var(--fg); background: var(--bg); }
header { padding: 24px 32px; border-bottom: 1px solid var(--border); }
header h1 { margin: 0 0 8px 0; font-size: 24px; }
header .meta { color: var(--muted); font-size: 13px; line-height: 1.6; }
header .meta span { display: inline-block; margin-right: 16px; }
main { padding: 24px 32px; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--border); }
th { font-weight: 600; }
.cat-row th { background: var(--catbg); color: var(--accent); font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; }
small { color: var(--muted); }
.delta-up { color: #b91c1c; font-weight: 600; }
.delta-down { color: #047857; font-weight: 600; }
footer { padding: 16px 32px; border-top: 1px solid var(--border); font-size: 12px; color: var(--muted); }
"""

  let doc = fmt("""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>isonim-tui benchmark report</title>
<style>{css}</style>
</head>
<body>
<header>
  <h1>isonim-tui benchmark report</h1>
  <div class="meta">
    <span><strong>Date:</strong> {esc(meta.date)}</span>
    <span><strong>Commit:</strong> {esc(meta.sha)}</span>
    <span><strong>Run:</strong> {esc(meta.quick)}</span><br>
    <span><strong>Host:</strong> {esc(meta.host)}</span>
    <span><strong>Kernel:</strong> {esc(meta.kernel)}</span>
    <span><strong>CPU:</strong> {esc(meta.cpu)}</span>
  </div>
</header>
<main>
<table>
<thead>{tableHead}</thead>
<tbody>
{rows}
</tbody>
</table>
</main>
<footer>
Generated by <code>scripts/render-bench-report.sh</code>. Self-contained
report (no external CSS/JS). Source data:
<code>bench-results/benchmark_results.json</code>.
</footer>
</body>
</html>
""")

  writeFile(outHtml, doc)
  stderr.writeLine fmt"[render] wrote {outHtml}"

main()
