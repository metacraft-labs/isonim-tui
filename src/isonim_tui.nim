## isonim-tui — production terminal renderer for IsoNim.
##
## Public top-level module. Re-exports the cell-grid primitives, the
## event types, the renderer backend, and (with M2) the headless
## driver / compositor / TerminalTestHarness / pilot / introspection
## API and the six snapshot encoders.
##
## See `Front-Ends/IsoNim/isonim-tui.milestones.org` in `codetracer-specs`
## for the full multi-milestone plan.

import isonim_tui/cells
import isonim_tui/events
import isonim_tui/renderer
import isonim_tui/text/width
import isonim_tui/text/ansi
import isonim_tui/text/content

# M2 surface
import isonim_tui/drivers/driver
import isonim_tui/drivers/headless_driver
import isonim_tui/compositor
import isonim_tui/testing/introspection
import isonim_tui/testing/harness
import isonim_tui/testing/pilot
import isonim_tui/testing/snapshot/plaintext as snapPlain
import isonim_tui/testing/snapshot/ansi as snapAnsi
import isonim_tui/testing/snapshot/cellmap as snapCellmap
import isonim_tui/testing/snapshot/svg as snapSvg
import isonim_tui/testing/snapshot/annotated_svg as snapAnnotatedSvg
import isonim_tui/testing/snapshot/treedump as snapTreedump
import isonim_tui/testing/snapshot/runner as snapRunner

# M3 surface — layout
import isonim_tui/layout/terminal_layout
import isonim_tui/layout/vertical
import isonim_tui/layout/horizontal
import isonim_tui/layout/grid
import isonim_tui/layout/stream
import isonim_tui/layout/dock
import isonim_tui/layout/arrange

# M4 surface — input parser (adapter over nim-termctl's L3 byte parser)
import isonim_tui/input/parser as inputParser
import isonim_tui/input/keymap as inputKeymap

export cells, events, renderer
export width, ansi, content
export driver, headless_driver, compositor
export introspection, harness, pilot
export snapPlain, snapAnsi, snapCellmap, snapSvg, snapAnnotatedSvg
export snapTreedump, snapRunner
export terminal_layout, vertical, horizontal, grid, stream, dock, arrange
export inputParser, inputKeymap
