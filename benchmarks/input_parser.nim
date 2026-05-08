## benchmarks/input_parser.nim
##
## Throughput of the M4 input parser. Drive ~1MB of pre-canned terminal
## bytes through the parser and report events/sec.

import std/[monotimes, times]

import isonim_tui/input/parser as inputParser

import bench_common

proc main() =
  let opts = parseBenchOptions()
  # Pre-canned input stream covers all major event categories: ASCII,
  # control bytes, function keys, navigation, mouse, bracketed paste.
  const sample =
    "abcdefghij" &                                            # 10 char keydowns
    "\x1b[A\x1b[B\x1b[C\x1b[D" &                              # 4 arrow keys
    "\x1bOP\x1bOQ\x1bOR\x1bOS" &                              # 4 fn keys
    "\x1b[15~\x1b[17~\x1b[18~\x1b[19~" &                      # 4 fn keys
    "\x1b[1~\x1b[4~\x1b[5~\x1b[6~" &                          # home/end/pgup/pgdn
    "\x1b[1;5A\x1b[1;5B" &                                    # 2 modifier
    "\x1b[Z\x1bA"                                             # 2 misc
  let bytesPerIter = sample.len

  let iterations = if opts.quick: 5_000 else: 50_000

  let totalBytes = bytesPerIter * iterations

  # Warm-up.
  block:
    var ip = initInputParser()
    for _ in 0 ..< 10:
      ip.feed(sample)
      ip.flush()
      discard ip.drain()

  var totalEvents = 0
  let t0 = getMonoTime()
  var ip = initInputParser()
  for _ in 0 ..< iterations:
    ip.feed(sample)
    ip.flush()
    let evs = ip.drain()
    totalEvents += evs.len
  let dtSec = inMicroseconds(getMonoTime() - t0).float / 1_000_000.0

  let evPerSec =
    if dtSec > 0.0: totalEvents.float / dtSec
    else: 0.0
  let mbPerSec =
    if dtSec > 0.0: (totalBytes.float / 1024.0 / 1024.0) / dtSec
    else: 0.0

  stderr.writeLine "input_parser: events=", totalEvents,
                   " sec=", dtSec, " ev/s=", evPerSec,
                   " MB/s=", mbPerSec

  writeBenchFragment(opts, [
    BenchEntry(name: "Input parser throughput",
               unit: "events/s",
               value: evPerSec,
               extra: $totalEvents & " events in " & $dtSec & "s (" &
                      $mbPerSec & " MB/s)"),
  ])

main()
