## isonim_tui/theme.nim
##
## Top-level facade for the theme package (M6).
##
## Re-exports:
##   - `theme/color.nim`     — `Color`, parsing (hex/rgb/hsl/named/ANSI),
##                             blending, alpha, gamma-corrected darken/
##                             lighten via Lab.
##   - `theme/design.nim`    — `ColorSystem`, `generate()`.
##   - `theme/theme.nim`     — `Theme` dataclass, `BUILTIN_THEMES`,
##                             `textual-dark` / `textual-light`.
##   - `theme/cascade.nim`   — `ThemeContext`, `computeStylesThemed`,
##                             `ThemeRegistry`, runtime theme switching.

import ./theme/color
import ./theme/design
import ./theme/theme as themeBase
import ./theme/cascade

export color
export design
export themeBase
export cascade
