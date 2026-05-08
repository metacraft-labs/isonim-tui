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

# M5 surface — TCSS engine (tokenize, parse, match, cascade, cache)
import isonim_tui/css/css as cssEngine

# M6 surface — theming (Color, ColorSystem, Theme, runtime switching)
import isonim_tui/theme as themeEngine

# M7 surface — animation engine (easing curves, animator, scalar/colour blends)
import isonim_tui/animation/easing as animEasing
import isonim_tui/animation/animator as animAnimator
import isonim_tui/animation/scalar as animScalar

# M9 surface — production POSIX driver. Imported behind
# `when not defined(windows)` because the implementation consumes the
# POSIX half of nim-termctl (raw mode, alt-screen, SIGWINCH self-pipe).
# The Windows analogue lands as M10's `windows_driver.nim`.
when not defined(windows):
  import isonim_tui/drivers/posix_driver as posixDriverMod

# M10 surface — production Windows driver. Imported behind
# `when defined(windows)` because the implementation reaches into the
# Win32 Console API (ReadConsoleInputW, SetConsoleCtrlHandler) and the
# Windows half of nim-termctl. The POSIX analogue is M9's
# `posix_driver.nim`.
when defined(windows):
  import isonim_tui/drivers/windows_driver as windowsDriverMod

# M11 surface — Tier-1a widget set (Static, Label, Container,
# Placeholder, Rule). The widget tree is built through the same
# renderer / compositor / cells pipeline so widgets compose cleanly
# with the M5/M6 cascade and the M8 layered compositor.
#
# M12 extends the same module with the Tier-1b interactive widgets
# (Button, Switch, Checkbox, RadioButton, RadioSet) plus the focus
# manager at `isonim_tui/focus/manager`.
import isonim_tui/widgets as tier1Widgets
import isonim_tui/focus/manager as focusManagerMod

# M15 surface — workers (background tasks, cooperative cancellation,
# per-harness manager, `{.work.}` decorator).
import isonim_tui/worker/worker as workerMod
import isonim_tui/worker/manager as workerManagerMod
import isonim_tui/worker/decorator as workerDecoratorMod

export cells, events, renderer
export width, ansi, content
export driver, headless_driver, compositor
export introspection, harness, pilot
export snapPlain, snapAnsi, snapCellmap, snapSvg, snapAnnotatedSvg
export snapTreedump, snapRunner
export terminal_layout, vertical, horizontal, grid, stream, dock, arrange
export inputParser, inputKeymap
export cssEngine
export themeEngine
export animEasing, animAnimator, animScalar
when not defined(windows):
  export posixDriverMod
when defined(windows):
  export windowsDriverMod
export tier1Widgets
export focusManagerMod
export workerMod, workerManagerMod, workerDecoratorMod
