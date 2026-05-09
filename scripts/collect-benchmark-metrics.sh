#!/usr/bin/env bash
# scripts/collect-benchmark-metrics.sh
#
# Runs the isonim-tui M24 benchmark suite end-to-end:
#   1. Builds each per-metric benchmark binary under bench-results/_bin
#   2. Runs each one in turn (with optional --quick), capturing JSON
#   3. Merges every fragment into a single
#      bench-results/benchmark_results.json in github-action-benchmark
#      format.
#
# Usage:
#   scripts/collect-benchmark-metrics.sh [--quick]
#   scripts/collect-benchmark-metrics.sh --output-dir=DIR
#
# Diagnostic output goes to stderr; the merged JSON is written to
# bench-results/benchmark_results.json (no stdout writes — the file
# is the contract).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QUICK=""
OUTPUT_DIR="$REPO_ROOT/bench-results"
KEEP_BINS=0
ONLY=""

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK="--quick" ;;
    --keep-bins) KEEP_BINS=1 ;;
    --output-dir=*) OUTPUT_DIR="${arg#--output-dir=}" ;;
    --only=*) ONLY="${arg#--only=}" ;;
  esac
done

log() { echo "[bench-metrics] $*" >&2; }

mkdir -p "$OUTPUT_DIR"
BIN_DIR="$OUTPUT_DIR/_bin"
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

# Ordered list of benchmark sources. Each name corresponds to
# benchmarks/<name>.nim and writes an array fragment to
# $OUTPUT_DIR/<name>.json.
ALL_BENCHES=(
  cold_start
  latency
  idle
  datatable_scroll
  compositor_diff
  memory
  animation
  css
  reactive
  snapshot
  input_parser
  vs_textual
)

if [ -n "$ONLY" ]; then
  IFS=',' read -ra BENCHES <<<"$ONLY"
else
  BENCHES=("${ALL_BENCHES[@]}")
fi

build_one() {
  local name="$1"
  local src="$REPO_ROOT/benchmarks/$name.nim"
  local out="$BIN_DIR/bench_$name"
  if [ ! -f "$src" ]; then
    log "ERROR: source not found: $src"
    return 1
  fi
  log "building $name"
  nim c "${NIM_FLAGS[@]}" "${NIM_PATHS[@]}" -o:"$out" "$src" >&2
}

run_one() {
  local name="$1"
  local out="$BIN_DIR/bench_$name"
  if [ ! -x "$out" ]; then
    log "ERROR: binary missing: $out"
    return 1
  fi
  log "running $name${QUICK:+ (quick)}"
  "$out" $QUICK --output-dir="$OUTPUT_DIR" --fragment="$name" >&2 || {
    log "WARN: $name exited non-zero; fragment may be missing"
  }
}

merge_fragments() {
  local merger="$BIN_DIR/merge_fragments"
  if [ ! -x "$merger" ]; then
    log "building merge_fragments helper"
    nim c "${NIM_FLAGS[@]}" "${NIM_PATHS[@]}" -o:"$merger" \
      "$REPO_ROOT/benchmarks/merge_fragments.nim" >&2
  fi
  log "merging fragments via merge_fragments helper"
  "$merger" "$OUTPUT_DIR" "${BENCHES[@]}" >&2
}

main() {
  for name in "${BENCHES[@]}"; do
    build_one "$name"
  done
  for name in "${BENCHES[@]}"; do
    run_one "$name"
  done

  merge_fragments

  log "summary:"
  if [ -f "$OUTPUT_DIR/benchmark_results.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq -r '.[] | "  " + .name + ": " + (.value|tostring) + " " + .unit' \
        "$OUTPUT_DIR/benchmark_results.json" >&2 || true
    else
      log "(install jq for a pretty summary)"
    fi
  fi

  if [ "$KEEP_BINS" -eq 0 ]; then
    rm -rf "$BIN_DIR"
  fi
}

main "$@"
