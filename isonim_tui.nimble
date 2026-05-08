# Package
version       = "0.1.0"
author        = "Metacraft Labs"
description   = "Production terminal renderer for IsoNim - cell primitives, RendererBackend conformance, future TUI runtime"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
# isonim provides the abstract_renderer concept this repo's TerminalRenderer
# satisfies and the renderer-agnostic component library that exercises it.
requires "isonim >= 0.1.0"
# nim-termctl owns the byte-level xterm/Kitty parser (L3); M4's input
# adapter (`src/isonim_tui/input/`) translates its events into the
# renderer's `TerminalEvent` shape.
requires "nim_termctl >= 0.1.0"
