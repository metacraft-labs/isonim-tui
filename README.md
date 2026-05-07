# isonim-tui

Production terminal renderer for [IsoNim](https://github.com/metacraft-labs/isonim).
Cell-grid primitives, RendererBackend conformance, and (in later
milestones) a full Textual-equivalent TUI runtime built on top of
`nim-pty`, `nim-libvterm`, and `nim-termctl`.

## Status — M0

Initial milestone: repo skeleton, cell primitives, renderer skeleton,
and the demo-renderer replacement in `isonim/`. No driver, no
compositor, no real terminal output yet — that lands in M2 (test
harness) and M8/M9/M10 (production drivers).

## Usage

```nim
import isonim_tui

let r = TerminalRenderer()
let div = r.createElement("div")
let txt = r.createTextNode("hello")
r.appendChild(div, txt)
echo textContent(div)  # "hello"
```

## Development

```sh
just build           # compile every test as a smoke check
just test            # run the default matrix point (orc + release + threads:on)
just lint            # nim check + nixfmt --check + markdownlint
just format          # nimpretty + nixfmt
```

See `AGENTS.md` for the full command list, project structure, and
architectural decisions.

## License

MIT — see `LICENSE`.
