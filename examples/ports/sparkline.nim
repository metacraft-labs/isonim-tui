## examples/ports/sparkline.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/sparkline.py` (M23 compat suite).
##
## Original (Python):
##
##   random.seed(73)
##   data = [random.expovariate(1 / 3) for _ in range(1000)]
##
##   class SparklineApp(App[None]):
##       DEFAULT_CSS = """
##       SparklineApp {
##           Sparkline { height: 1fr; }
##       }
##       """
##       def compose(self) -> ComposeResult:
##           yield Sparkline(data, summary_function=max)
##           yield Sparkline(data, summary_function=mean)
##           yield Sparkline(data, summary_function=min)
##
## Three sparklines stacked vertically over a fixed deterministic
## series. The M21 `Sparkline` widget directly supports `sumMax`,
## `sumMean`, and `sumMin` — no auxiliary code needed.
##
## The dataset is generated with a deterministic LCG so the port is
## reproducible without depending on Python's `random` module.

import std/math
import isonim_tui

# Deterministic dataset matching the *shape* of Python's
# `random.expovariate(1/3)` series at `seed(73)` (length 1000). The
# concrete values won't match Textual byte-for-byte (different RNG),
# but the M23 contract is "cell-content identical" against our own
# golden — once recorded the values stay stable.
proc deterministicSeries(): seq[float64] =
  ## A simple LCG-fed exponential CDF inversion, parameterised so the
  ## series has the same statistical character (mean ≈ 3.0,
  ## right-skewed) as the Python original.
  result = newSeq[float64](1000)
  var state: uint64 = 73'u64
  for i in 0 ..< 1000:
    state = state * 6364136223846793005'u64 + 1442695040888963407'u64
    # Take the top 53 bits as a uniform float in [0, 1).
    let u = (state shr 11).float64 / (1'u64 shl 53).float64
    # Inverse CDF of Exp(1/3): -3*ln(1-u). Guard u==1 so ln stays finite.
    let safe = if u >= 0.999999: 0.999999 else: u
    result[i] = -3.0 * ln(1.0 - safe)

proc buildSparklineApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  let data = deterministicSeries()
  let third = max(1, h.rows div 3)

  let s1 = newSparkline(r, data = data,
                        width = h.cols, height = third, summary = sumMax)
  r.appendChild(root, s1.node)

  let s2 = newSparkline(r, data = data,
                        width = h.cols, height = third, summary = sumMean)
  r.appendChild(root, s2.node)

  let s3 = newSparkline(r, data = data,
                        width = h.cols, height = h.rows - 2 * third,
                        summary = sumMin)
  r.appendChild(root, s3.node)

  root
