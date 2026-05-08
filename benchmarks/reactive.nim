## benchmarks/reactive.nim
##
## Measures "Reactive signal write→effect latency": the average wall
## time from `signal.val = x` to the dependent effect re-running. The
## reactive engine is `isonim/core` (re-exported via `rxcore`) — same
## graph code that powers the entire IsoNim component tree.
##
## We report microseconds (the median is sub-microsecond on a warm
## cache; even at the p99 it should sit in the low tens of µs).

import std/[monotimes, times]

import isonim/rxcore

import bench_common

proc main() =
  let opts = parseBenchOptions()
  let writes = if opts.quick: 1000 else: 10_000

  var samples: seq[float] = @[]
  createRoot do (dispose: proc()):
    let s = createSignal(0)
    var observed = 0
    createRenderEffect do:
      observed = s.val
    # Warm-up: 100 writes — observed lags by one cycle.
    for i in 1 .. 100:
      s.val = i
    # Measured loop. Each write→effect cycle is a separate timing.
    for i in 1 .. writes:
      let t0 = getMonoTime()
      s.val = i
      # `observed` is updated synchronously by createRenderEffect;
      # if it's not yet equal to i the schedule fired async and we
      # still record the delta.
      let dtNs = inNanoseconds(getMonoTime() - t0).float
      samples.add dtNs / 1000.0   # convert to microseconds
    discard observed
    dispose()

  let p50 = percentile(samples, 0.5)
  let p99 = percentile(samples, 0.99)

  stderr.writeLine "reactive: writes=", samples.len,
                   " p50=", p50, " us p99=", p99, " us"

  writeBenchFragment(opts, [
    BenchEntry(name: "Reactive signal write->effect latency",
               unit: "us",
               value: p50,
               extra: $writes & " writes, p50 (p99=" & $p99 & "us)"),
  ])

main()
