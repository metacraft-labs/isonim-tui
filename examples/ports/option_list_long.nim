## examples/ports/option_list_long.nim — Nim port of Textual's
## `tests/snapshot_tests/snapshot_apps/option_list_long.py`
## (M23 compat suite).
##
## Original (Python):
##
##   class LongOptionListApp(App[None]):
##       def compose(self) -> ComposeResult:
##           yield OptionList(*[Option(f"This is option #{n}")
##                              for n in range(100)])
##
## A 100-row `OptionList` exercising the M14 widget's scroll viewport.
## We render the same labels and let the harness window size pick the
## visible rows.
##
## DM-M4: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. The post-mount Pilot needs the OptionList's
## `.node` to focus, so we build the widget outside the `ui()` block
## and embed its node via `embedNode` (mirrors DM-M3's
## `listview_index` precedent).

import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

proc buildOptionListLongApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer

  var rows: seq[OptionRow] = @[]
  for n in 0 ..< 100:
    rows.add OptionRow(kind: orkOption, id: "opt" & $n,
                       label: "This is option #" & $n)

  let ol = newOptionList(r, rows = rows,
                         width = max(20, h.cols - 2),
                         viewportHeight = max(4, h.rows - 2),
                         border = bsSolid)

  result = ui(r):
    tdiv(class = "option-list-long-port"):
      embedNode(ol.node)

  # Mirror the focus on mount so the highlighted-row chrome appears.
  let p = newPilot(h)
  p.focus(ol.node)
