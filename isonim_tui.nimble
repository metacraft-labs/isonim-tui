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
