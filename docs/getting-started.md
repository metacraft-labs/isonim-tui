# Getting Started with IsoNim-TUI

`isonim-tui` is the production terminal renderer for IsoNim. It ships with
a Textual-equivalent widget set, a TCSS engine, animation, theming,
workers, a command palette, and a real-stack snapshot test harness. This
guide walks through installation and a minimal "hello world" application.

## Installation

The repository lives at `metacraft/isonim-tui` and is part of the
`metacraft` workspace. The build resolves sibling repos via the
`config.nims` at the repo root, so the standard development workflow is:

```sh
cd metacraft/isonim-tui
nix develop                # enters the devShell with nim + just
just build                 # smoke-compile every test
just test                  # run the default matrix point
```

For consumers, vendor the repo and add an `import isonim_tui` clause.
The single top-level module re-exports every subsystem you need.

## Hello World — minimal app

The smallest runnable program mounts a `Label` under a
`TerminalTestHarness`. The harness packages a renderer, headless driver,
compositor, virtual clock, animator, focus manager, and worker manager
into one ref object — exactly what every example and test relies on.

```nim
import isonim_tui

proc main() =
  let h = newTerminalTestHarness(40, 5)
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let label = newLabel(r, "Hello, IsoNim-TUI!")
    r.appendChild(root, label.node)
    root)
  echo "rendered:"
  echo encodePlaintext(h.driver.buffer)
  h.dispose()

when isMainModule:
  main()
```

Compile and run from the repo root:

```sh
nim c -r path/to/hello.nim
```

`encodePlaintext` is one of the six snapshot formats — handy for
inspecting the cell grid without leaving the test harness.

## Mounting against a real terminal (POSIX)

For an interactive run, swap the headless driver for the production
`PosixDriver` (M9). The driver opens raw mode, switches to the alt
screen, parses input through nim-termctl, and handles SIGWINCH via a
self-pipe.

```nim
import isonim_tui

when not defined(windows):
  proc main() =
    var driver = newPosixDriver()
    driver.start()
    defer: driver.stop()
    # ... event loop using driver.poll(), compositor.paint(driver), ...
```

Examples that demonstrate the full event loop and compositor pipeline
live under `examples/`. Start with `examples/calculator/` for a
keyboard-driven mini app, or `examples/markdown_viewer/` for a single
widget hosting a bundled README.

## Where to next

- `viewmodel.md` — the IsoNim ViewModel pattern for cross-platform apps.
- `widgets.md` — the full widget gallery.
- `tcss-reference.md` — TCSS selectors and properties.
- `snapshot-testing.md` — how `TerminalTestHarness` and the six snapshot
  formats fit into your test suite.
- `debugging.md` — recording, replay, and time-travel introspection.
