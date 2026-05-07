## isonim-tui — production terminal renderer for IsoNim.
##
## Public top-level module. Re-exports the cell-grid primitives, the
## event types, and the renderer backend so consumers can write a
## single `import isonim_tui` and get the M0 surface in one go.
##
## See `Front-Ends/IsoNim/isonim-tui.milestones.org` in `codetracer-specs`
## for the full multi-milestone plan; this module re-exports M0
## deliverables only — drivers / compositor / harness / widget tiers
## land in later milestones and will be re-exported from here as they
## arrive.

import isonim_tui/cells
import isonim_tui/events
import isonim_tui/renderer
import isonim_tui/text/width
import isonim_tui/text/ansi
import isonim_tui/text/content

export cells, events, renderer
export width, ansi, content
