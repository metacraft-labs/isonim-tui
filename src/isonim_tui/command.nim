## isonim_tui/command.nim — Command palette public surface (M16).
##
## Re-exports the fuzzy matcher and the command-palette modal so
## consumers can `import isonim_tui` (which re-exports this module)
## and immediately reach `newCommandPalette`, `newSimpleProvider`,
## `Hit`, `Matcher`, `fuzzyScore`, etc.

import command/fuzzy
import command/palette

export fuzzy
export palette
