## isonim_tui/dsl/widget_blocks.nim — DSL-friendly widget wrappers.
##
## ## Why this module exists
##
## Inside a `ui(r):` block (the Karax-style DSL from
## `isonim/src/isonim/dsl/ui.nim`), the macro recognises three kinds of
## children:
##
##   1. *Known HTML tags* (`tdiv`, `span`, `button`, ...) — emitted as
##      `createElement` + `setAttribute` + child sub-tree.
##   2. *Bare `nnkCall` / `nnkCommand` nodes whose name is unknown and
##      whose args are all positional* — treated as node-returning Nim
##      expressions and appended to the parent via `appendChild`.
##   3. *Anything else* — passed through verbatim, **not** appended to
##      the parent.
##
## In particular, any call with **named arguments** (`name = value`)
## is treated by `isElementCall` (in `isonim/dsl/ui.nim`) as an HTML
## element — which causes `width = cols` and friends to be expanded
## as `setAttribute`/`setStyle` on a synthetic element instead of
## passed to the wrapped widget constructor. And calling a widget
## constructor's `.node` accessor (e.g. `newButton(r, "x").node`) is
## an `nnkDotExpr`, not an `nnkCall`, so the DSL passes it through
## verbatim — yielding a free-standing `TerminalNode` value the
## compiler rejects with `expression ... has to be used (or
## discarded)`.
##
## Both gaps push us toward thin wrapper procs:
##
##   - take their args **positionally** (no named-argument calls
##     inside `ui(...)`),
##   - return a `TerminalNode` directly (not a widget object), and
##   - keep the underlying constructor's parameter order so the
##     widget's full configuration surface is reachable.
##
## ## Naming convention
##
## Every wrapper has the prefix `w` followed by the widget's natural
## name (`wHeader`, `wFooter`, `wLabel`, `wButton`, ...). The wrapper
## takes the same parameters as the underlying constructor in the
## same order, returns the widget's `.node` field, and never holds a
## reference to the widget object — the renderer keeps the element
## tree alive via parent pointers.
##
## Wrappers live next to the DSL macro on purpose: they are not part
## of the imperative widget API (you still call `newButton` directly
## when you want the `ButtonWidget` return value to wire up handlers
## or to mutate state). They exist purely to make the DSL ergonomic.
## Add new wrappers here as DM-M1 through DM-M6 land — keep this
## file flat (one wrapper per widget constructor).
##
## ## Example
##
## ```nim
## import isonim_tui
## import isonim_tui/dsl/widget_blocks
## import isonim/dsl/ui
##
## let root = ui(r):
##   tdiv(class = "task-app-demo"):
##     wHeader(r, "Tasks", "demo", h.cols)
##     tdiv(class = "task-list"):
##       for t in vm.tasks:
##         tdiv:
##           wLabel(r, (if t.completed: "[x] " else: "[ ] ") & t.name)
##     wFooter(r, bindings, h.cols)
## ```
##
## ## Cross-link
##
## See `docs/dsl-pattern.md` for the full pattern used across the
## DM-M1 through DM-M6 refactor.

import ../renderer
import ../text/content
import ../css/properties
import ../widgets/header
import ../widgets/footer
import ../widgets/label
import ../widgets/static
import ../widgets/button

# ----------------------------------------------------------------------------
# Header / Footer
# ----------------------------------------------------------------------------

proc wHeader*(renderer: TerminalRenderer; title, subtitle: string;
              width: int; tall: bool = false): TerminalNode =
  ## DSL-friendly wrapper around `newHeader`. Returns the rendered
  ## header's `.node` so it can be used directly as a child of a
  ## `ui(r):` block. Inside a `ui()` block, call this with positional
  ## arguments only — see the module docstring.
  newHeader(renderer, title = title, subtitle = subtitle,
            width = width, tall = tall).node

proc wFooter*(renderer: TerminalRenderer;
              bindings: openArray[FooterBinding];
              width: int; compact: bool = true): TerminalNode =
  ## DSL-friendly wrapper around `newFooter`. Positional args only
  ## inside a `ui()` block.
  newFooter(renderer, bindings = bindings, width = width,
            compact = compact).node

# ----------------------------------------------------------------------------
# Label
# ----------------------------------------------------------------------------

proc wLabel*(renderer: TerminalRenderer; content: Content;
             width: int = 0): TerminalNode =
  ## DSL-friendly wrapper around `newLabel(renderer, content, width)`.
  newLabel(renderer, content, width).node

proc wLabel*(renderer: TerminalRenderer; text: string;
             width: int = 0): TerminalNode =
  ## DSL-friendly wrapper around `newLabel(renderer, text, width)`.
  newLabel(renderer, text, width).node

# ----------------------------------------------------------------------------
# Static
# ----------------------------------------------------------------------------

proc wStatic*(renderer: TerminalRenderer; content: string;
              width, height: int;
              border: BorderStyle = bsNone;
              borderColor: string = "";
              scrollable: bool = false): TerminalNode =
  ## DSL-friendly wrapper around `newStatic`. The parameter order
  ## mirrors the underlying constructor so the full configuration
  ## surface (border style, colour, scrolling) is reachable
  ## positionally inside a `ui()` block.
  newStatic(renderer, content = content, width = width, height = height,
            border = border, borderColor = borderColor,
            scrollable = scrollable).node

# ----------------------------------------------------------------------------
# Button
# ----------------------------------------------------------------------------

proc wButton*(renderer: TerminalRenderer; label: string;
              width: int;
              onClick: proc()): TerminalNode =
  ## DSL-friendly wrapper around `newButton` for the common case:
  ## label + explicit width + click handler. The parameter order
  ## diverges from `newButton` (which interleaves variant / border /
  ## borderColor / disabled between `width` and `onClick`) so callers
  ## can pass a handler positionally inside a `ui()` block without
  ## threading defaults for every intermediate optional argument.
  ## Variants / non-default borders / disabled state aren't yet
  ## reachable through this wrapper — add an overload here when a
  ## DM-M2+ demo needs them.
  newButton(renderer, label = label, width = width,
            onClick = onClick).node
