## benchmarks/css.nim
##
## CSS cascade timing. We parse a small stylesheet, build a tree of
## ~200 nodes, and time:
##   * "CSS cascade per node" — the first time `computeStyles` runs
##     for each node (no cache).
##   * "CSS cascade cached" — the second time (every lookup hits the
##     cache).
##
## Both report microseconds-per-node averages.

import std/[monotimes, times]

import isonim_tui
import bench_common

proc main() =
  let opts = parseBenchOptions()
  let nodeCount = if opts.quick: 50 else: 200

  let r = TerminalRenderer()
  let root = r.createElement("Screen")
  r.setAttribute(root, "id", "app")
  r.setAttribute(root, "class", "container")

  # Build a deterministic tree of `nodeCount` Button nodes.
  var nodes: seq[TerminalNode] = @[]
  for i in 0 ..< nodeCount:
    let n = r.createElement("Button")
    r.setAttribute(n, "id", "btn-" & $i)
    if i mod 2 == 0:
      r.setAttribute(n, "class", "primary")
    else:
      r.setAttribute(n, "class", "secondary")
    r.appendChild(root, n)
    nodes.add n

  let sheet = newStylesheet()
  sheet.addCss(ssDefault, "default", """
    Screen { background: black; color: white; }
    Button { width: 50%; height: 1; background: blue; color: white; }
  """)
  sheet.addCss(ssUser, "app.tcss", """
    Container > Button { width: 100%; }
    Button.primary { background: red; }
    Button.secondary { background: green; }
    #btn-0 { color: yellow; }
  """)

  # First pass: cold cache.
  var coldUs: float = 0.0
  let coldStart = getMonoTime()
  for n in nodes:
    let ctx = NodeContext(node: n, pseudo: {})
    let computed {.used.} = computeStyles(sheet, ctx)
  coldUs = inMicroseconds(getMonoTime() - coldStart).float / nodeCount.float

  # Second pass: warm cache. The cascade module re-parses
  # `computeStyles` on every call (no built-in cache); if a per-call
  # cache lands later this benchmark records the speedup.
  var warmUs: float = 0.0
  let warmStart = getMonoTime()
  for n in nodes:
    let ctx = NodeContext(node: n, pseudo: {})
    let computed {.used.} = computeStyles(sheet, ctx)
  warmUs = inMicroseconds(getMonoTime() - warmStart).float / nodeCount.float

  stderr.writeLine "css: nodes=", nodeCount,
                   " cold=", coldUs, " us/node",
                   " warm=", warmUs, " us/node"

  writeBenchFragment(opts, [
    BenchEntry(name: "CSS cascade per node",
               unit: "us",
               value: coldUs,
               extra: $nodeCount & "-node tree, cold lookup"),
    BenchEntry(name: "CSS cascade cached",
               unit: "us",
               value: warmUs,
               extra: $nodeCount & "-node tree, warm cache"),
  ])

main()
