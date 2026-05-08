#!/usr/bin/env bash
# scripts/profile-on-regression.sh
#
# Run a single benchmark binary under `perf record` (Linux) and emit a
# flamegraph at bench-results/flamegraph-<name>.svg. Invoked by CI when
# a hard-threshold regression triggers; the resulting artifact is
# uploaded alongside the failure.
#
# Usage:
#   scripts/profile-on-regression.sh <bench_name>
#
# Requires: perf, FlameGraph (stackcollapse-perf.pl, flamegraph.pl).
# When tools are missing we still write a stub artifact so the CI
# upload step always finds the expected file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BENCH="${1:-}"
if [ -z "$BENCH" ]; then
  echo "usage: $0 <bench_name>" >&2
  exit 64
fi

OUTPUT_DIR="$REPO_ROOT/bench-results"
mkdir -p "$OUTPUT_DIR"
BIN="$OUTPUT_DIR/_bin/bench_$BENCH"
SVG="$OUTPUT_DIR/flamegraph-$BENCH.svg"
LOG="$OUTPUT_DIR/flamegraph-$BENCH.log"

log() { echo "[profile-on-regression] $*" >&2; }

if [ ! -x "$BIN" ]; then
  log "binary not found: $BIN — building it"
  bash "$SCRIPT_DIR/collect-benchmark-metrics.sh" --quick --keep-bins --only="$BENCH"
fi

if [ ! -x "$BIN" ]; then
  log "ERROR: still no binary at $BIN"
  echo "<svg><text x='10' y='20'>profile unavailable: binary missing</text></svg>" > "$SVG"
  exit 0
fi

if ! command -v perf >/dev/null 2>&1; then
  log "perf not installed; writing stub flamegraph"
  echo "<svg><text x='10' y='20'>profile unavailable: perf not installed</text></svg>" > "$SVG"
  exit 0
fi

PERF_DATA="$OUTPUT_DIR/perf-$BENCH.data"
log "running: perf record -F 99 -g -o $PERF_DATA $BIN --quick"
perf record -F 99 -g -o "$PERF_DATA" "$BIN" --quick \
  --output-dir="$OUTPUT_DIR" --fragment="$BENCH-profile" 2>"$LOG" || {
    log "WARN: perf record exited non-zero (continuing)"
}

if command -v stackcollapse-perf.pl >/dev/null 2>&1 && \
   command -v flamegraph.pl >/dev/null 2>&1; then
  log "rendering flamegraph SVG"
  perf script -i "$PERF_DATA" 2>>"$LOG" \
    | stackcollapse-perf.pl 2>>"$LOG" \
    | flamegraph.pl --title "isonim-tui $BENCH" > "$SVG" 2>>"$LOG"
else
  log "FlameGraph tools not available; using perf-report text fallback"
  perf report -i "$PERF_DATA" --stdio > "$OUTPUT_DIR/perf-report-$BENCH.txt" \
    2>>"$LOG" || true
  echo "<svg><text x='10' y='20'>perf data captured; see perf-report-$BENCH.txt</text></svg>" > "$SVG"
fi

log "wrote $SVG"
