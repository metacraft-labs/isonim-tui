#!/usr/bin/env bash
# scripts/render-bench-report.sh
#
# Generates `bench-results/report.html` — a self-contained HTML report
# of the M24 benchmark suite. The report has no external dependencies
# (inline CSS/JS, no <script src=…>) so it can be opened in a browser
# offline or served as a CI artifact.
#
# Inputs:
#   bench-results/benchmark_results.json — the merged metrics file.
#
# Output:
#   bench-results/report.html
#
# Optional env / flags:
#   BASELINE_JSON=path  → side-by-side comparison column
#   --baseline=path     → same, as a flag
#   --output-dir=DIR    → override default bench-results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="$REPO_ROOT/bench-results"
BASELINE_JSON="${BASELINE_JSON:-}"
QUICK_FLAG="${QUICK:-full}"

for arg in "$@"; do
  case "$arg" in
    --output-dir=*) OUTPUT_DIR="${arg#--output-dir=}" ;;
    --baseline=*) BASELINE_JSON="${arg#--baseline=}" ;;
    --quick) QUICK_FLAG="quick" ;;
  esac
done

INPUT_JSON="$OUTPUT_DIR/benchmark_results.json"
REPORT_HTML="$OUTPUT_DIR/report.html"
BIN_DIR="$OUTPUT_DIR/_bin"

log() { echo "[render-bench] $*" >&2; }

if [ ! -f "$INPUT_JSON" ]; then
  log "ERROR: $INPUT_JSON not found; run scripts/collect-benchmark-metrics.sh first"
  exit 1
fi

mkdir -p "$BIN_DIR"

NIM_PATHS=(
  "--path:$REPO_ROOT/src"
  "--path:$REPO_ROOT/tests"
  "--path:$REPO_ROOT/benchmarks"
  "--path:$REPO_ROOT/benchmarks/standard_app"
  "--path:$REPO_ROOT/../isonim/src"
  "--path:$REPO_ROOT/../nim-termctl/src"
  "--path:$REPO_ROOT/../nim-pty/src"
  "--path:$REPO_ROOT/../nim-faststreams"
  "--path:$REPO_ROOT/../nim-stew"
  "--path:$REPO_ROOT/../nim-everywhere/src"
)

NIM_FLAGS=(
  "--styleCheck:off"
  "--mm:orc"
  "-d:release"
  "--threads:on"
  "--hints:off"
  "--warnings:off"
)

# Gather metadata.
SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
HOST="$(uname -n 2>/dev/null || echo unknown)"
KERNEL="$(uname -sr 2>/dev/null || echo unknown)"
CPUMODEL="unknown"
if [ -f /proc/cpuinfo ]; then
  CPUMODEL="$(grep -m1 'model name' /proc/cpuinfo | sed 's/^[^:]*:[[:space:]]*//' || true)"
elif command -v sysctl >/dev/null 2>&1; then
  CPUMODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
fi

RENDERER="$BIN_DIR/render_report"
if [ ! -x "$RENDERER" ]; then
  log "building render_report helper"
  nim c "${NIM_FLAGS[@]}" "${NIM_PATHS[@]}" -o:"$RENDERER" \
    "$REPO_ROOT/benchmarks/render_report.nim" >&2
fi

ARGS=(
  "$INPUT_JSON"
  "$REPORT_HTML"
  "--sha=$SHA"
  "--date=$DATE"
  "--host=$HOST"
  "--kernel=$KERNEL"
  "--cpu=$CPUMODEL"
  "--quick=$QUICK_FLAG"
)
if [ -n "$BASELINE_JSON" ]; then
  ARGS+=("--baseline=$BASELINE_JSON")
fi

"$RENDERER" "${ARGS[@]}" >&2
log "wrote $REPORT_HTML"
