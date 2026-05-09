# Snapshot Testing

The M2 `TerminalTestHarness` is the user-facing test API for
`isonim-tui`. Every later milestone tests through it: drivers,
compositor, layout, CSS, theming, animation, widgets, command palette,
workers, recording / replay.

## TerminalTestHarness

```nim
type TerminalTestHarness* = ref object
  cols*, rows*: int
  renderer*: TerminalRenderer
  driver*: HeadlessDriver
  compositor*: Compositor
  clock*: TestClock
  root*: TerminalNode
  animator*: Animator
  focusManager*: FocusManager
  workerManager*: WorkerManager
  ...
```

Each harness bundles **everything an app needs to run**:
- a fresh renderer with a per-thread node-id counter,
- a HeadlessDriver that owns a `ScreenBuffer` + recorded byte stream,
- a Compositor with strip cache,
- a virtual `TestClock` (so `advance(ms)` is deterministic),
- the M7 `Animator`, M12 `FocusManager`, M15 `WorkerManager`.

Construct with `newTerminalTestHarness(cols, rows)`, mount with
`h.mount(buildProc)`, drive with `h.flush()` / `h.advance(ms)` / a
`Pilot`, and snapshot with `h.snap(name)`.

## Pilot

`Pilot` is the high-level driver. Its surface mirrors Textual's
`pilot.py` — `press`, `type`, `click`, `hover`, `focus`, `paste`,
`waitFor`, `waitForAnimation`, etc.

```nim
let p = newPilot(h)
p.focus(button.node)
p.press("enter")
p.type("hello, world")
p.waitForAnimation()
discard h.snap("after_submit")
```

Every pilot action funnels through the same event-emission path the
production driver uses, so tests cover the real input-parsing and
event-routing code paths.

## Six snapshot formats

Each call to `h.snap(name)` writes (or compares against) six files
under `tests/snapshots/<name>/`:

| File | Format | Purpose |
| --- | --- | --- |
| `plaintext.txt` | UTF-8 cell grid | Eyeball-friendly. Easiest diff. |
| `ansi.ansi` | Cell grid + SGR escapes | Real terminal output. |
| `cellmap.json` | Per-cell JSON triple | Machine-readable; SGR-stable. |
| `svg.svg` | Vector SVG of the buffer | Visual diff in a browser. |
| `annotated.svg` | SVG + bbox / focus / hover overlays | M25 introspection. |
| `treedump.txt` | Element tree dump | Verifies node identity and layout regions. |

The `cellmap.json` format is the gold-standard for byte-stable
diffing: SGR ordering can differ between runs without affecting cell
identity.

## Recording mode

First run with `SNAP_RECORD=1` records every absent golden:

```sh
SNAP_RECORD=1 nim c -r tests/test_my_widget.nim
```

Subsequent runs (without the env var) compare. On mismatch the runner
appends to `tests/snapshots/_report.html` — a single artifact lists
every diff so a CI run surfaces all regressions in one place.

The `tests/test_snapshot_record_mode.nim` and
`tests/test_snapshot_stable_across_runs.nim` tests gate the
record / replay contract.

## Choosing what to snapshot

For pure layout / paint regressions, `plaintext.txt` plus
`treedump.txt` is enough. For visual regressions add `svg.svg` (it
diffs cleanly in a browser). For SGR-sensitive bugs use
`cellmap.json`. Recording all six formats is cheap (~100µs per
snapshot) and gives the next investigator every angle on the failure.

## Parallel test isolation

The `tests/test_harness_isolation_parallel.nim` corpus runs four
threads × 100 elements each and asserts no node-id collisions, no
worker cross-talk, and no shared snapshot state. The guarantees:

- `nextTerminalNodeId` is a `{.threadvar.}` — each thread gets its
  own counter.
- The snapshot accumulator is also threadvar.
- Each harness owns its own animator / focus manager / worker
  manager.

Run your test suite with `nim c --threads:on … -d:release` and the
existing snapshot tests show how to opt into parallel execution.
