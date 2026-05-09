# Animation

The M7 animator drives every time-based effect in `isonim-tui`:
collapsible expand/collapse, modal slide-in, toast fade-out, progress
bar fills, loading spinners, and any user code calling `animate(...)`.

The implementation lives at `src/isonim_tui/animation/`. The full
surface is re-exported by the top-level `isonim_tui` module.

## Architecture

The animator is owned by the `TerminalTestHarness` (and by the runtime
driver in production). It runs against a `TestClock` so tests advance
time deterministically.

```nim
type
  Animator* = ref object
    clock*: TestClock
    framesPerSecond*: int
    activeAnimations: ...
```

Every active animation has a unique `AnimationKey` — typically derived
from `(node.id, propertyName)`. New animations targeting the same key
cancel the previous one.

## Easings

The 33 easing curves are byte-identical with Textual's `_easing.py`:

```
linear        in_sine        out_sine        in_out_sine
in_quad       out_quad       in_out_quad
in_cubic      out_cubic      in_out_cubic
in_quart      out_quart      in_out_quart
in_quint      out_quint      in_out_quint
in_expo       out_expo       in_out_expo
in_circ       out_circ       in_out_circ
in_back       out_back       in_out_back
in_elastic    out_elastic    in_out_elastic
in_bounce     out_bounce     in_out_bounce
none          (and the duration-zero shortcut)
```

`tests/test_easing_byte_parity.nim` verifies output byte-for-byte
against captured Textual reference vectors.

## API

### `animateFloat`

The primary entry point for scalar interpolations:

```nim
animator.animateFloat(
  key = AnimationKey(nodeId: node.id, property: "opacity"),
  startVal = 0.0, endVal = 1.0,
  durationMs = 250, easing = easeOutCubic,
  onStep = proc(v: float) = node.setStyle("opacity", $v),
  onComplete = proc() = discard)
```

### `cancel` / `cancelAll`

Stop a running animation. `cancel(key)` removes one entry; `cancelAll`
clears the entire active set (used on harness teardown).

### `tick`

Advances the animator by the supplied duration. The harness wires this
into `advance(ms)` so test-time progression is automatic.

### Color blends

The M7 module includes a colour-aware blend that operates in linear
RGB space (gamma correct). Used by every widget that animates a
foreground / background colour. See
`tests/test_color_blend_gamma_correct.nim` and
`tests/test_color_blend_in_animation.nim` for the exact contract.

## Pilot integration

The pilot exposes two helpers for tests:

- `p.waitForAnimation()` — block (in virtual time) until the active
  animation set drains.
- `p.waitForScheduledAnimations()` — wait specifically for animations
  scheduled by a recent action (e.g. a button press that triggered an
  expand).

These run under the test clock, so they never burn wall-time.
