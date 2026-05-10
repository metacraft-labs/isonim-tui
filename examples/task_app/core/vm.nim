## examples/task_app/core/vm.nim — re-export shim for the canonical
## task-app ViewModel.
##
## Per EX-M1 (see
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`),
## the shared task-app core was promoted to the canonical
## `isonim-examples` repository. This file remains in `isonim-tui`
## solely as a re-export shim so the existing M22 test surface and
## leaves keep importing `../core/vm` without churn.
##
## A future milestone (EX-M2) migrates the leaves into
## `isonim-examples` too, at which point this shim can be deleted.
##
## The path-based dep on `isonim-examples` is wired in `isonim-tui`'s
## Justfile (`src-paths` includes `--path:../isonim-examples`).

import task_app/core/vm
export vm
