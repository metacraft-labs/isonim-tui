## examples/task_app/core/views.nim — include shim for the canonical
## task-app Layer-2 view template.
##
## Per EX-M1 (see
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`),
## the shared task-app core was promoted to the canonical
## `isonim-examples` repository. This file remains in `isonim-tui`
## only because the composition roots `include` (rather than `import`)
## the views module — `include` is textual paste, so we re-include the
## canonical file. Names from the platform leaves resolve in the
## composition root's scope, exactly as before.
##
## A future milestone (EX-M2) migrates the leaves into
## `isonim-examples` too, at which point this shim can be deleted.
##
## The path-based dep on `isonim-examples` is wired in `isonim-tui`'s
## Justfile (`src-paths` includes `--path:../isonim-examples`).

include task_app/core/views
