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
## ## `embedNode` identity wrapper
##
## Some demos need to construct a widget *outside* the `ui()` block —
## either because they retain the widget object for post-mount
## scripting (focus / keyboard pilots / mutation), or because the
## widget needs `.append(child.node)` calls the DSL can't express. The
## DSL only recognises positional *calls* as node-returning children;
## a bare `lv.node` is `nnkDotExpr` and the macro passes it through
## verbatim, leaving the compiler to reject it with "expression has to
## be used (or discarded)". `embedNode(lv.node)` wraps the dot-expr
## in a call so the DSL appends it like any other widget node.
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
import ../testing/harness
import ../text/content
import ../css/properties
import ../widgets/header
import ../widgets/footer
import ../widgets/label
import ../widgets/static
import ../widgets/button
import ../widgets/input
import ../widgets/listview
import ../widgets/directory_tree
import ../widgets/textarea
import ../widgets/sparkline
import ../widgets/datatable
import ../widgets/markdown
import ../widgets/placeholder
import ../widgets/rule
import ../widgets/progress_bar

# ----------------------------------------------------------------------------
# Identity wrapper for already-built nodes
# ----------------------------------------------------------------------------

proc embedNode*(n: TerminalNode): TerminalNode {.inline.} = n
  ## Identity wrapper that lets a `ui(r):` block append a node that
  ## was constructed outside the block (e.g. when the caller retains
  ## the widget object for post-mount Pilot scripting). See the module
  ## docstring for why the DSL needs the call-form rather than a bare
  ## `lv.node` dot-expression.

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

proc wButton*(renderer: TerminalRenderer; label: string;
              width: int = 0): TerminalNode =
  ## DSL-friendly wrapper around `newButton` for a click-handler-less
  ## button (the M23 ports just want to render a labelled box —
  ## activation isn't part of the snapshot contract). `width = 0`
  ## inherits the auto-size behaviour of `newButton` (label + 4
  ## padding cells). First needed by DM-M3's `button_widths` port.
  newButton(renderer, label = label, width = width).node

proc wButtonStyled*(renderer: TerminalRenderer; label: string;
                    width: int;
                    variant: ButtonVariant = bvDefault;
                    border: BorderStyle = bsRound;
                    borderColor: string = "";
                    disabled: bool = false;
                    onClick: proc() = nil): TerminalNode =
  ## DSL-friendly wrapper around `newButton` exposing the styled
  ## surface (variant / border / borderColor / disabled). Mirrors
  ## `newButton`'s parameter order so the full configuration is
  ## reachable positionally inside a `ui()` block. First needed by
  ## DM-M3's `button_outline` port (which wants to set `borderColor =
  ## "white"`); use the simpler `wButton` overloads when only label
  ## + width + handler are needed.
  newButton(renderer, label = label, width = width, variant = variant,
            border = border, borderColor = borderColor,
            disabled = disabled, onClick = onClick).node

# ----------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------

proc wInput*(renderer: TerminalRenderer; value, placeholder: string;
             width: int; border: BorderStyle;
             onChange: proc(newValue: string)): TerminalNode =
  ## DSL-friendly wrapper around `newInput` for the typical demo case:
  ## seed value, placeholder text, explicit width, border style, and a
  ## change handler. The parameter order diverges from `newInput` (which
  ## interleaves password / borderColor / disabled / maxLength /
  ## validator / suggester / onChange / onSubmit) so callers can pass
  ## the handler positionally inside a `ui()` block without threading
  ## defaults for every intermediate optional argument. Add an overload
  ## here when a future demo needs password / suggester / validator
  ## wiring through the DSL.
  newInput(renderer, value = value, placeholder = placeholder,
           width = width, border = border, onChange = onChange).node

# ----------------------------------------------------------------------------
# ListView
# ----------------------------------------------------------------------------

proc wListView*(renderer: TerminalRenderer;
                items: openArray[ListItem];
                width, viewportHeight: int;
                border: BorderStyle = bsNone): TerminalNode =
  ## DSL-friendly wrapper around `newListView`. Drops the optional
  ## borderColor / color / onHighlight / onActivate slots; add an
  ## overload here when a future demo needs them.
  newListView(renderer, items = items, width = width,
              viewportHeight = viewportHeight, border = border).node

# ----------------------------------------------------------------------------
# DirectoryTree
# ----------------------------------------------------------------------------

proc wDirectoryTree*(renderer: TerminalRenderer; path: string;
                     width, viewportHeight: int;
                     border: BorderStyle = bsNone): TerminalNode =
  ## DSL-friendly wrapper around `newDirectoryTree`. Drops the optional
  ## showRoot / borderColor / color / onSelect slots; add an overload
  ## here when a future demo needs them.
  newDirectoryTree(renderer, path = path, width = width,
                   viewportHeight = viewportHeight, border = border).node

# ----------------------------------------------------------------------------
# TextArea
# ----------------------------------------------------------------------------

proc wTextArea*(renderer: TerminalRenderer; text: string;
                width, viewportHeight: int;
                border: BorderStyle = bsRound;
                readOnly: bool = false): TerminalNode =
  ## DSL-friendly wrapper around `newTextArea`. Drops the optional
  ## borderColor / color / tabSize / softWrap / language / disabled /
  ## maxUndoDepth / onChange slots; add an overload here when a future
  ## demo needs them.
  newTextArea(renderer, text = text, width = width,
              viewportHeight = viewportHeight, border = border,
              readOnly = readOnly).node

# ----------------------------------------------------------------------------
# RichLog
# ----------------------------------------------------------------------------
#
# No `wRichLog` wrapper: demos that need a RichLog (e.g. log_viewer)
# also need the widget object to call `body.write(line)`, so they
# construct it outside the `ui()` block via `newRichLog` and append
# `body.node` to the tree directly. Add a wrapper here when a future
# demo uses RichLog purely as a static, unpopulated node.

# ----------------------------------------------------------------------------
# Sparkline
# ----------------------------------------------------------------------------

proc wSparkline*(renderer: TerminalRenderer; data: openArray[float64];
                 width, height: int;
                 summary: SparklineSummary = sumMax): TerminalNode =
  ## DSL-friendly wrapper around `newSparkline`. Drops the optional
  ## minColor / maxColor slots; add an overload here when a future
  ## demo needs gradient configuration.
  newSparkline(renderer, data = data, width = width, height = height,
               summary = summary).node

# ----------------------------------------------------------------------------
# DataTable
# ----------------------------------------------------------------------------

proc wDataTable*(renderer: TerminalRenderer;
                 columns: openArray[ColumnDef];
                 rows: openArray[RowData];
                 viewportHeight: int;
                 border: BorderStyle = bsNone): TerminalNode =
  ## DSL-friendly wrapper around `newDataTable`. Drops the optional
  ## borderColor / color / onActivate / onSelectionChange slots; add
  ## an overload here when a future demo needs them.
  newDataTable(renderer, columns = columns, rows = rows,
               viewportHeight = viewportHeight, border = border).node

# ----------------------------------------------------------------------------
# Markdown
# ----------------------------------------------------------------------------

proc wMarkdown*(renderer: TerminalRenderer; source: string;
                width: int;
                border: BorderStyle = bsNone): TerminalNode =
  ## DSL-friendly wrapper around `newMarkdown`. Drops the optional
  ## borderColor / color / codeBlockColor / headingColor / quoteColor /
  ## linkColor slots; add an overload here when a future demo needs
  ## per-element colour configuration.
  newMarkdown(renderer, source = source, width = width,
              border = border).node

# ----------------------------------------------------------------------------
# Placeholder
# ----------------------------------------------------------------------------

proc wPlaceholder*(renderer: TerminalRenderer; name: string;
                   width: int = 20; height: int = 5): TerminalNode =
  ## DSL-friendly wrapper around `newPlaceholder`. Mirrors the
  ## constructor's positional surface (name + width + height). First
  ## needed by DM-M3's `placeholder_disabled` port; the disabled-band
  ## styling stays a setStyle/setAttribute follow-up at the call site
  ## (the placeholder itself doesn't carry a `disabled` constructor
  ## arg).
  newPlaceholder(renderer, name = name, width = width,
                 height = height).node

# ----------------------------------------------------------------------------
# Rule
# ----------------------------------------------------------------------------

proc wRule*(renderer: TerminalRenderer;
            orientation: RuleOrientation = roHorizontal;
            width: int = 0; height: int = 1;
            style: BorderStyle = bsSolid;
            color: string = ""): TerminalNode =
  ## DSL-friendly wrapper around `newRule`. Mirrors the constructor's
  ## positional surface. First needed by DM-M3's `rules` port (which
  ## stamps every BorderStyle horizontally and vertically).
  newRule(renderer, orientation = orientation, width = width,
          height = height, style = style, color = color).node

# ----------------------------------------------------------------------------
# ProgressBar
# ----------------------------------------------------------------------------

proc wProgressBar*(h: TerminalTestHarness;
                   total: float64 = 100.0;
                   progress: float64 = 0.0;
                   width: int = 30;
                   showPercent: bool = true;
                   barColor: string = "blue";
                   completeColor: string = "green";
                   bgColor: string = ""): TerminalNode =
  ## DSL-friendly wrapper around `newProgressBar`. Diverges from the
  ## other `w*` wrappers in taking a `TerminalTestHarness` (not a
  ## `TerminalRenderer`) because `newProgressBar` itself needs the
  ## harness for animator wiring (M21 contract). Mirrors the
  ## constructor's positional surface. First needed by DM-M3's
  ## `progress_gradient` port.
  newProgressBar(h, total = total, progress = progress, width = width,
                 showPercent = showPercent, barColor = barColor,
                 completeColor = completeColor, bgColor = bgColor).node
