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

import isonim_tui

proc buildOptionListLongApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")

  var rows: seq[OptionRow] = @[]
  for n in 0 ..< 100:
    rows.add OptionRow(kind: orkOption, id: "opt" & $n,
                       label: "This is option #" & $n)

  let ol = newOptionList(r, rows = rows,
                         width = max(20, h.cols - 2),
                         viewportHeight = max(4, h.rows - 2),
                         border = bsSolid)
  r.appendChild(root, ol.node)

  # Mirror the focus on mount so the highlighted-row chrome appears.
  let p = newPilot(h)
  p.focus(ol.node)
  root
