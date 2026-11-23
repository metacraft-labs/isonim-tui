window.BENCHMARK_DATA = {
  "lastUpdate": 1795433081126,
  "repoUrl": "https://github.com/metacraft-labs/isonim-tui",
  "entries": {
    "isonim-tui Performance (Linux)": [
      {
        "commit": {
          "author": {
            "email": "zahary@gmail.com",
            "name": "zah",
            "username": "zah"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "63421dbb075e608ffea4bfb7f8429c682ec4a760",
          "message": "Merge pull request #13 from metacraft-labs/ci/benchmark-linux-dedicated-labels\n\nci(benchmark): select the Linux benchmark runner as [linux, x64, benchmark]; fix the benchmark so it runs and passes\n\nThe Linux benchmark passed on gpu-server-001-mcl-bench-001 (run 45075372992,\nat f6a6226), with all 7 hard thresholds met. RSS per added widget is\n0.424 KB against the 10 KB limit, and idle RSS is 4.0 MB.\n\nComparison with dev's red baseline at b848618: 78 checks fail on this PR,\nagainst 55 failing jobs on dev. All 55 also fail here. The other 23 were\ncancelled on dev and never ran:\n- The 18 linux-arm64 Charter jobs and 3 linux-arm64 Test jobs fail like\n  their x64 twins on dev (test_threadvar_id_isolation.nim(41, 18): undeclared\n  identifier 'Channel').\n- The 5 \"repro build/test\" legs fail on \"cross-repo producer isonim source\n  revision mismatch\". repro.lock expects isonim 8621593ce42f, a revision\n  GitHub does not have, so this fails at the old isonim pin as well as the\n  new one.\n\nNone of these is in a file this PR changes.",
          "timestamp": "2026-11-23T07:40:11+02:00",
          "tree_id": "e1ffbe033799eb6a8741fbc0f514ead7c13d7484",
          "url": "https://github.com/metacraft-labs/isonim-tui/commit/63421dbb075e608ffea4bfb7f8429c682ec4a760"
        },
        "date": 1795433080037,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "Cold start to first paint",
            "value": 10.318,
            "unit": "ms",
            "extra": "median of 5 runs, 30-widget standard app"
          },
          {
            "name": "Input latency p50",
            "value": 0.359,
            "unit": "ms",
            "extra": "200 keystrokes typed into Input widget"
          },
          {
            "name": "Input latency p99",
            "value": 6.746499999999994,
            "unit": "ms",
            "extra": "200 keystrokes typed into Input widget"
          },
          {
            "name": "Idle CPU",
            "value": 0,
            "unit": "%",
            "extra": "observed over 1000 ms"
          },
          {
            "name": "DataTable scroll repaint cells",
            "value": 176.84,
            "unit": "cells",
            "extra": "50 scrolls on 10000-row table"
          },
          {
            "name": "DataTable scroll FPS",
            "value": 1741.4928076347046,
            "unit": "fps",
            "extra": "50 scrolls on 10000-row table"
          },
          {
            "name": "Single-cell mutation byte volume",
            "value": 9,
            "unit": "bytes",
            "extra": "type one char into Input on standard app"
          },
          {
            "name": "Compositor frame paint",
            "value": 3.724,
            "unit": "ms",
            "extra": "single-cell mutation paint"
          },
          {
            "name": "Strip cache hit rate",
            "value": 98,
            "unit": "%",
            "extra": "200 steady-state DataTable scrolls (9800 hits / 10000 lookups)"
          },
          {
            "name": "RSS at idle (standard app)",
            "value": 4.0078125,
            "unit": "MB",
            "extra": "30-widget standard app, post first paint"
          },
          {
            "name": "RSS per added widget",
            "value": 0.424,
            "unit": "KB",
            "extra": "amortised over 1000 Static widgets"
          },
          {
            "name": "Animation frame rate",
            "value": 2216.3939270806395,
            "unit": "fps",
            "extra": "60-frame easing animation, virtual clock"
          },
          {
            "name": "CSS cascade per node",
            "value": 6.1,
            "unit": "us",
            "extra": "50-node tree, cold lookup"
          },
          {
            "name": "CSS cascade cached",
            "value": 42.32,
            "unit": "us",
            "extra": "50-node tree, warm cache"
          },
          {
            "name": "Reactive signal write->effect latency",
            "value": 0.312,
            "unit": "us",
            "extra": "1000 writes, p50 (p99=0.46855999999999953us)"
          },
          {
            "name": "Snapshot capture (six formats)",
            "value": 10.030999999999999,
            "unit": "ms",
            "extra": "20 iterations, all six encoders"
          },
          {
            "name": "Input parser throughput",
            "value": 1738324.2554177772,
            "unit": "events/s",
            "extra": "150000 events in 0.08629s (4.807606068336061 MB/s)"
          },
          {
            "name": "vs. Textual cold start ratio",
            "value": 0,
            "unit": "ratio",
            "extra": "deferred (Textual subprocess unavailable on bench runner)"
          },
          {
            "name": "vs. Textual p50 latency ratio",
            "value": 0,
            "unit": "ratio",
            "extra": "deferred (Textual subprocess unavailable on bench runner)"
          },
          {
            "name": "vs. Textual idle CPU ratio",
            "value": 0,
            "unit": "ratio",
            "extra": "deferred (Textual subprocess unavailable on bench runner)"
          }
        ]
      }
    ]
  }
}