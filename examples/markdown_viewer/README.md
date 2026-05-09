# IsoNim-TUI

A Textual-equivalent TUI runtime built on the IsoNim reactive core.

## Features

- Real terminal driver (POSIX + Windows)
- TCSS engine with cascade and theming
- Tier-1 / Tier-2 / Tier-3 widget set
- Animator with 33 easings
- Snapshot test harness with six output formats

## Quick start

```nim
import isonim_tui

let h = newTerminalTestHarness(40, 5)
h.mount(proc(r: TerminalRenderer): TerminalNode =
  let root = r.createElement("div")
  r.appendChild(root, newLabel(r, "Hello!").node)
  root)
echo encodePlaintext(h.driver.buffer)
```

> Every example under `examples/` ships with a recorded golden
> snapshot under `tests/snapshots/examples/<name>/`.
