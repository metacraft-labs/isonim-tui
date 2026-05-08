## benchmarks/animation.nim
##
## Drives the animator through a single 1-second 60Hz animation and
## counts how many frames complete inside that window. The harness's
## virtual clock means we don't actually wait — we step the animator
## at fixed virtual-time increments and record real time per step.
## Reports effective FPS = (frames completed) / (real wall time / 1000).

import std/monotimes

import isonim_tui
import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  let frameCount = if opts.quick: 60 else: 240
  const frameMs = 1000.0 / 60.0

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  let handles = buildStandardApp(h)

  var animatedValue = 0.0
  h.animator.animateFloat(
    targetId = handles.header.node.id,
    attribute = "anim-bench",
    startValue = 0.0,
    endValue = 1.0,
    durationMs = frameCount.float * frameMs,
    setter = proc(v: float64) =
      animatedValue = v,
    onComplete = nil)

  let t0 = getMonoTime()
  for i in 0 ..< frameCount:
    h.advanceMs(frameMs)
  let dtMs = elapsedMs(t0)

  let fps =
    if dtMs > 0.0: frameCount.float / (dtMs / 1000.0)
    else: 0.0

  stderr.writeLine "animation: frames=", frameCount, " realMs=", dtMs,
                   " fps=", fps, " final=", animatedValue

  writeBenchFragment(opts, [
    BenchEntry(name: "Animation frame rate",
               unit: "fps",
               value: fps,
               extra: $frameCount & "-frame easing animation, virtual clock"),
  ])

  h.dispose()

main()
