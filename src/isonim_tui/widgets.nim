## isonim_tui/widgets.nim — Tier-1a widget set (M11).
##
## Single point of import for the foundational widget primitives that
## every interactive widget in M12+ sits inside. Re-exports every
## public symbol from the per-widget modules so callers can write
## `import isonim_tui/widgets` and access `newStatic`, `newLabel`,
## `newContainer`, `newPlaceholder`, `newRule` without hunting for
## the right submodule.

import widgets/borders
import widgets/static as staticMod
import widgets/label as labelMod
import widgets/container as containerMod
import widgets/placeholder as placeholderMod
import widgets/rule as ruleMod

export borders
export staticMod
export labelMod
export containerMod
export placeholderMod
export ruleMod
