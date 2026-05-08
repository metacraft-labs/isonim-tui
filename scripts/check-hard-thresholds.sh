#!/usr/bin/env bash
# scripts/check-hard-thresholds.sh
#
# Hard-failure gate. Reads bench-results/benchmark_results.json and
# fails (exit 1) when any of these absolute targets are exceeded:
#
#   Cold start to first paint    < 50 ms
#   Input latency p50            < 16 ms
#   Input latency p99            < 33 ms
#   Idle CPU                     < 0.5 %
#   RSS at idle (standard app)   < 30 MB
#   RSS per added widget         < 10 KB
#   Strip cache hit rate         > 95 %
#
# These mirror the absolute targets in the M24 milestone test list
# ("bench_*_meets_target"). The CI workflow combines this gate with
# github-action-benchmark's relative 120% baseline check; together they
# implement the spec's hard-threshold table.
#
# When run locally with no JSON file, the script returns 0 (no-op).
# When the JSON exists but is malformed, it returns 1 — the contract
# is "the file must be readable".

set -euo pipefail

INPUT="${1:-bench-results/benchmark_results.json}"

if [ ! -f "$INPUT" ]; then
  echo "[hard-threshold] $INPUT not found; skipping (run scripts/collect-benchmark-metrics.sh first)" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# We use a small Nim helper because the merge/render scripts already do.
# This keeps the dependency surface aligned with `nix develop` (no Python).
HELPER="$REPO_ROOT/bench-results/_bin/check_thresholds"
if [ ! -x "$HELPER" ]; then
  mkdir -p "$(dirname "$HELPER")"
  nim c --styleCheck:off --hints:off --warnings:off \
    --mm:orc -d:release \
    --path:"$REPO_ROOT/src" \
    -o:"$HELPER" \
    "$REPO_ROOT/benchmarks/check_thresholds.nim" >&2
fi

"$HELPER" "$INPUT"
