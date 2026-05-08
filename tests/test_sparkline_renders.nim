## test_sparkline_renders — Tier-3e Sparkline rendering checks. The
## test exercises bucket partitioning, summary functions, and the
## empty / single-sample fast paths.

import unittest
import isonim_tui

suite "M21: Sparkline rendering":

  test "sparkline_default_renders_one_row":
    let h = newTerminalTestHarness(20, 2)
    var sp: SparklineWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sp = newSparkline(r, data = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
                        width = 8, height = 1)
      r.appendChild(root, sp.node)
      root)
    h.flush()
    # Eight buckets, one row — the rightmost cell should hit the
    # full-block glyph because the series is monotonically increasing
    # and the last bucket carries the highest summary.
    let lastCol = h.cellAt(0, 7)
    check lastCol.rune.int32 == 0x2588 # █
    h.dispose()

  test "sparkline_empty_data_uses_floor":
    let h = newTerminalTestHarness(20, 2)
    var sp: SparklineWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sp = newSparkline(r, width = 6, height = 1)
      r.appendChild(root, sp.node)
      root)
    h.flush()
    # Floor-bar (▁) all the way across.
    for col in 0 ..< 6:
      check h.cellAt(0, col).rune.int32 == 0x2581
    h.dispose()

  test "sparkline_single_sample_full_block":
    let h = newTerminalTestHarness(20, 2)
    var sp: SparklineWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      sp = newSparkline(r, data = [42.0], width = 5, height = 1)
      r.appendChild(root, sp.node)
      root)
    h.flush()
    for col in 0 ..< 5:
      check h.cellAt(0, col).rune.int32 == 0x2588
    h.dispose()

  test "sparkline_summary_modes":
    let h = newTerminalTestHarness(20, 2)
    var sp: SparklineWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      sp = newSparkline(r, data = [1.0, 5.0, 1.0, 5.0],
                        width = 2, height = 1, summary = sumMin)
      let root = r.createElement("div")
      r.appendChild(root, sp.node)
      root)
    sp.setSummary(sumMax)
    sp.setSummary(sumMean)
    sp.setSummary(sumLast)
    sp.setSummary(sumFirst)
    h.flush()
    check sp.data.len == 4
    h.dispose()

  test "sparkline_appendvalue_retains":
    let h = newTerminalTestHarness(20, 2)
    var sp: SparklineWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      sp = newSparkline(r, width = 4, height = 1)
      let root = r.createElement("div")
      r.appendChild(root, sp.node)
      root)
    for i in 0 ..< 100:
      sp.appendValue(i.float64, retainCount = 8)
    check sp.data.len == 8
    check sp.data[0] == 92.0
    check sp.data[^1] == 99.0
    h.dispose()
