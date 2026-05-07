# isonim-tui

Production terminal renderer for IsoNim. The follow-up to the demo-only
`isonim/src/isonim/renderers/terminal.nim` (now `terminal_demo.nim`),
this repo is the foundation of a full Textual-equivalent TUI runtime
landing across milestones M0-M27.

## What this library does (M0 surface)

`isonim-tui` provides:

- **Cell-grid primitives** (`Cell`, `Strip`, `ScreenBuffer`) — value
  types with cached display width and content hash for O(rows) diff on
  unchanged buffers. The compositor (M2/M8) consumes `diff` regions to
  emit minimal ANSI updates.
- **Production `TerminalRenderer`** that satisfies
  `checkRendererBackend[TerminalRenderer, TerminalNode]()`. Same
  RendererBackend surface as `MockRenderer`, the renamed demo
  `terminal_demo.TerminalRenderer`, and `WebRenderer` — so a
  renderer-agnostic component compiles unchanged across all four
  backends.
- **Value-typed events** (`TerminalEvent`, `KeyEvent`, `MouseEvent`) —
  shape parity with `isonim/src/isonim/web/dom_api.nim` so handler
  bodies stay portable.

Drivers (POSIX / Windows), compositor, layout, CSS engine, animation,
widgets — every later milestone builds on the M0 surface. See
`Front-Ends/IsoNim/isonim-tui.milestones.org` in `codetracer-specs`
for the full plan.

## Commands

```sh
just build           # compile every test as a smoke check
just test            # run the default matrix point (orc + release + threads:on)
just lint            # nim check + nixfmt --check
just format          # nimpretty + nixfmt
```

Charter matrix recipes (CI runs each as a separate matrix cell):

```sh
just test-arc        # arc memory manager, all three modes
just test-orc        # orc memory manager, all three modes
just test-refc       # refc memory manager, all three modes
just test-threads-off
just test-asan       # AddressSanitizer (Linux/clang)
just test-ubsan      # UndefinedBehaviorSanitizer
just test-tsan       # ThreadSanitizer
just test-lsan       # LeakSanitizer
just test-valgrind   # secondary leak verification
just test-all        # everything that runs on a Linux runner
```

Per repo-requirements §3 (build, test, lint, format with `fmt` alias,
bench, bench --quick, `t` short alias), `bump-version` and the
language-specific sub-recipes (`lint-nim`, `lint-nix`, `lint-markdown`,
`format-nim`, `format-nix`, `test-unit`, `test-integration`).

## Project structure

```
src/
  isonim_tui.nim                       # public top-level - re-exports cells/events/renderer
  isonim_tui/cells.nim                 # Cell, Strip, ScreenBuffer + diff
  isonim_tui/events.nim                # TerminalEvent, KeyEvent, MouseEvent (value types)
  isonim_tui/renderer.nim              # TerminalRenderer (RendererBackend conformance)
tests/
  test_renderer_concept_conformance.nim  # checkRendererBackend + cross-renderer counter
  test_threadvar_id_isolation.nim        # 4 threads x 100 elements, no id collision
  test_strip_diff.nim                    # 1 / 5 / 2-disjoint diff regions
  test_screenbuffer_diff_empty.nim       # buf.diff(buf) == [] for any size
  test_repo_requirements_*.nim           # flake / Justfile / .envrc / AGENTS.md / CI conformance
.github/workflows/ci.yml                 # lint, test, charter matrix, sanitizers, valgrind, nix-build
flake.nix                                # nix devShell + checks (pre-commit via git-hooks.nix)
Justfile                                 # build/test/lint/format + matrix + sanitizers
isonim_tui.nimble                        # single-source-of-truth version
```

## Architectural decisions

- **Why isonim-tui doesn't reimplement signals.** The reactive core
  (`signals`, `computation`, `owner`, `effects`) lives in `isonim/`.
  `isonim-tui` consumes it as a sibling-repo dependency and is only
  responsible for the renderer + driver + widget tier. Forking the
  reactive core would force divergence across `isonim`, `isonim-tui`,
  `isonim-cocoa`, `isonim-gpui`, etc.
- **Why we use Yoga via FFI (M3).** Textual's CSS layout engine is a
  full Yoga-equivalent flexbox. We don't reimplement it; M3 binds Yoga
  through a thin C-FFI shim. Decision deferred from M0.
- **Where the no-mocks rule lives.** Charter-mandated: every test in
  this repo exercises the real renderer / cell types / driver. No
  fakes, no stubs. Synthetic input events at the OS boundary
  (`Pilot.press(...)`) and the `TestClock` are the only permitted
  fakes — both are real, isonim-canonical surfaces.
- **Cell primitives are value types only.** Charter §1: `Cell`,
  `Strip`, `ScreenBuffer`, every `Color`, and every event payload is a
  plain `object`. `ref object` is allowed in the renderer's element
  tree (mirrors `MockNode`) for ergonomic parity, not in the cell
  layer.
- **No raw `ptr` in the public API.** Use `openArray[T]`, `seq[byte]`,
  `string`, or typed handles.
- **Per-thread monotonic id counter.** The renderer's
  `nextTerminalNodeId` is a `{.threadvar.}`. The bug that motivated
  M0's demo-renderer rename was a plain `var` global there — when
  parallel test harnesses landed they would have aliased ids.
  `mock_dom.nim:40` had it right; we mirror that exactly.

## Coding conventions

- `--styleCheck:usages --styleCheck:error` is enforced — use `camelCase`
  identifiers. The Justfile bakes this into every nim invocation.
- Public types in `cells.nim` are value `object`s. `ref object` is
  forbidden in the cell-grid layer.
- Public APIs never expose raw `ptr`. Use `openArray[T]`, `seq[byte]`,
  `string`, or typed handles.
- `cast` is forbidden in the public API; use sparingly internally and
  justify each use in a comment.
- Every test is a real-stack integration test — no mocks. Tests
  exercise the real renderer / real cell types / (later) real ptys.

## Specs

The authoritative specifications for this library live in the
`codetracer-specs` repo:

- `Front-Ends/IsoNim/isonim-tui.milestones.org` — the full milestone
  plan (M0 through M29) and the "Memory-safety + testing-rigor
  charter".
- `metacraft-specs/policies/repo-requirements.md` — repo-level
  conformance (flake, Justfile, .envrc, hooks, CI).

When user requests change the public API, update the spec in the same
change set.
