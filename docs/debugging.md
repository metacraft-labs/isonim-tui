# Debugging

The M25 milestone shipped advanced introspection: deterministic
session **recording**, time-travel **replay**, layout assertions, and
an HTML timeline. The implementation lives at
`src/isonim_tui/testing/` (`recorder.nim`, `replayer.nim`,
`recording_types.nim`, `assertions.nim`, plus the timeline encoder
under `snapshot/timeline.nim`).

## Recording

A `Recording` is a value-typed record of every input event, paint, and
state mutation that flowed through a harness during a session. Capture
one with the recorder:

```nim
import isonim_tui

let h = newTerminalTestHarness(60, 20)
let rec = newRecorder(h)
h.mount(buildApp)
let p = newPilot(h)
p.press("ctrl+n")
p.type("hello")
p.press("enter")
let recording = rec.finish()
```

The recorder hooks into the harness's event log and the compositor's
paint callback. Every paint stamps a virtual-time tick; every input
event records the seq number.

## Round-trip serialisation

Recordings serialise to a stable line-oriented text format so they're
diffable in PR review and durable across upgrades. The contract is
gated by `tests/test_recording_round_trip_serialisation.nim`.

## Replayer

Replay a recording into a fresh harness:

```nim
let h2 = newTerminalTestHarness(60, 20)
h2.mount(buildApp)
replay(recording, h2)
# h2 is now in the same state as the original h.
```

`tests/test_record_replay_byte_identical.nim` proves the replay path
produces byte-identical bytes on the driver's emitted stream.

## Timeline

`h.snapTimeline(recording, "session")` writes
`tests/snapshots/session/_timeline.html` — an interactive page that
walks frame by frame through the recording. Useful when a regression
is hard to triage from a single static snapshot.

```nim
discard h.snapTimeline(recording, "user_session")
```

The HTML strips dynamic timestamps before comparing so the golden is
byte-stable. `tests/test_timeline_html_diffable.nim` gates that
contract.

## Layout assertions

The M25 assertions module catches subtle layout bugs that pure
snapshot diffs miss:

- `assertNoOverlap(h)` — fails if any two sibling regions overlap
  (commonly caused by mis-aligned positions when a parent's flex
  flow is wrong).
- `assertSinglePassPaint(h)` — fails if the compositor wrote the same
  cell more than once in a single paint (catches double-painting
  regressions in the strip cache).

Both are exercised by
`tests/test_assertNoOverlap_catches_misalignment.nim` and
`tests/test_assertSinglePassPaint.nim`.

## Annotated SVG

Pass a set of overlay flags to `h.snap(name, overlays)` to get an
inspector SVG showing focus rings, bounding boxes, hover targets,
and dirty regions. Useful when a snapshot diff says "something
moved" but you can't see where.

```nim
let svg = h.snap("debug", {aoFocus, aoBoundingBox})
writeFile("debug.svg", svg)
```

## Debug CLI

A dedicated debug CLI ships under `src/isonim_tui/cli/`. Its
entry point loads a recording and prints a per-frame summary, which
is enough to triage most issues without reaching for a debugger.

## When a test fails

Every snapshot mismatch lands in `tests/snapshots/_report.html` —
open it in a browser, and you get a side-by-side golden vs. actual
diff for each format. For deeper investigation:

1. Re-run with `SNAP_RECORD=1` to overwrite the golden — only do
   this once you're convinced the new behaviour is correct.
2. Add a `Recording` capture around the failing scenario; run
   `snapTimeline` to see the frame-by-frame story.
3. Drop in `assertNoOverlap` / `assertSinglePassPaint` — they often
   localise layout regressions a snapshot diff hides.
