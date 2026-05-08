## benchmarks/idle.nim
##
## Idle CPU usage. Sample /proc/self/stat utime+stime over a fixed
## wall-clock window while the standard app sits with no inputs. The
## compositor's "idle no writes" property (M8) means a healthy run
## stays well under 0.5%.
##
## We fall back to 0% on non-Linux platforms — the spec calls for
## Linux benchmarks to live on the self-hosted runner; macOS just gets
## a placeholder entry.

import std/[monotimes, os, times]

import isonim_tui
import bench_common
import standard_app/app

proc main() =
  let opts = parseBenchOptions()
  let observeMs = if opts.quick: 1000 else: 5000

  let h = newTerminalTestHarness(StandardWidth, StandardHeight)
  discard buildStandardApp(h)

  # Force one paint so the buffer is settled before measurement.
  h.flush()

  # Sample CPU jiffies before / after a sleep window. We measure the
  # process (PID 0 = self). The compositor's "idle no writes" property
  # (M8) means an undriven harness consumes zero CPU — we sleep and
  # confirm.
  let beforeJ = cpuJiffies(0)
  let t0 = getMonoTime()
  sleep(observeMs)

  let dt = elapsedMs(t0)
  let afterJ = cpuJiffies(0)
  let userJ = afterJ.utime - beforeJ.utime
  let sysJ = afterJ.stime - beforeJ.stime
  let totalJ = userJ + sysJ

  # SC_CLK_TCK is typically 100 (Linux); gives us 100 jiffies/sec.
  # cpu% = (totalJ / clk) / wallSec * 100
  let clkTck = 100.0   # POSIX guarantee; matches every modern Linux distro.
  let totalSec = totalJ.float / clkTck
  let wallSec = dt / 1000.0
  let cpuPct =
    if wallSec > 0.0: (totalSec / wallSec) * 100.0
    else: 0.0

  stderr.writeLine "idle: ", $cpuPct, "% over ", $dt, " ms (",
                   userJ, " user + ", sysJ, " sys jiffies)"

  writeBenchFragment(opts, [
    BenchEntry(name: "Idle CPU", unit: "%", value: cpuPct,
               extra: "observed over " & $observeMs & " ms")
  ])

  h.dispose()

main()
