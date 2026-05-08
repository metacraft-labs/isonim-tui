## test_textual_compat — M23 Textual Compatibility Suite.
##
## For each Nim port under `examples/ports/` we mount the application
## under `TerminalTestHarness`, snapshot it (six formats), and gate
## the result against a stored golden under
## `tests/snapshots/m23_<name>/`.
##
## The M23 milestone notes "Textual subprocess parity is deferred from
## earlier milestones" — this test stops at golden parity. Goldens are
## recorded once (set `SNAP_RECORD=1`); subsequent runs diff against
## them. Mismatches write `tests/snapshots/_report.html`.
##
## Tolerance (per the milestone):
##   * Cell content is identical (plaintext / cellmap / svg).
##   * SGR ordering may differ — we compare against the isonim-tui
##     encoder's own output (byte-stable across runs).
##   * Visual result is identical.
##
## Pragmatic scope: 8 representative ports out of the 30+ vision
## (failure infrastructure shared via the snapshot runner; remaining
## ports tracked as Appendix C follow-ups).

import unittest
import isonim_tui

import ../examples/ports/button_outline
import ../examples/ports/button_widths
import ../examples/ports/placeholder_disabled
import ../examples/ports/rules
import ../examples/ports/sparkline as portSparkline
import ../examples/ports/progress_gradient
import ../examples/ports/listview_index
import ../examples/ports/data_table_row_labels

# A tagged-failure registry. When a port is known to drift from the
# Textual reference (or its golden has not yet been recorded against a
# stable terminal-size policy), we record the reason here so CI can
# distinguish "the port broke" from "the port is intentionally
# scope-deferred". Empty today — every shipped port is expected to
# pass golden parity once recorded.
const TaggedFailures: array[0, tuple[name, reason: string]] = []

proc isTaggedFailure(name: string): bool =
  for tf in TaggedFailures:
    if tf.name == name: return true
  false

template snapPort(testName, snapName: string; cols, rows: int;
                  builder: untyped): untyped =
  ## Mount one port, take its snapshot, gate against the golden.
  let h = newTerminalTestHarness(cols, rows)
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    builder(h))
  let matched = h.snap(snapName)
  if not isTaggedFailure(testName):
    check matched
  h.dispose()

suite "M23: Textual Compatibility Suite — verbatim app ports":

  test "test_compat_button_outline":
    snapPort("test_compat_button_outline", "m23_button_outline",
             40, 5, buildButtonOutlineApp)

  test "test_compat_button_widths":
    snapPort("test_compat_button_widths", "m23_button_widths",
             80, 10, buildButtonWidthsApp)

  test "test_compat_placeholder_disabled":
    snapPort("test_compat_placeholder_disabled",
             "m23_placeholder_disabled",
             40, 12, buildPlaceholderDisabledApp)

  test "test_compat_rules":
    snapPort("test_compat_rules", "m23_rules",
             60, 20, buildRulesApp)

  test "test_compat_sparkline":
    snapPort("test_compat_sparkline", "m23_sparkline",
             60, 9, portSparkline.buildSparklineApp)

  test "test_compat_progress_gradient":
    snapPort("test_compat_progress_gradient", "m23_progress_gradient",
             60, 3, buildProgressGradientApp)

  test "test_compat_listview_index":
    snapPort("test_compat_listview_index", "m23_listview_index",
             40, 14, buildListViewIndexApp)

  test "test_compat_data_table_row_labels":
    snapPort("test_compat_data_table_row_labels",
             "m23_data_table_row_labels",
             80, 14, buildDataTableRowLabelsApp)

  test "test_compat_suite_8_apps":
    ## Aggregate gate. Mirrors the milestone's
    ## `test_compat_suite_30_apps` (scoped down to the 8 ports
    ## actually shipped — see README under `examples/ports/`). Mounts
    ## every port in turn, snapshots, counts matches; the suite passes
    ## when every non-tagged port matches its golden.
    var passed = 0
    var failed: seq[string] = @[]

    template runOne(name: string; cols, rows: int; builder: untyped) =
      let h = newTerminalTestHarness(cols, rows)
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        discard r
        builder(h))
      if h.snap(name):
        inc passed
      elif not isTaggedFailure(name):
        failed.add name
      h.dispose()

    runOne("m23_suite_button_outline", 40, 5,
           buildButtonOutlineApp)
    runOne("m23_suite_button_widths", 80, 10,
           buildButtonWidthsApp)
    runOne("m23_suite_placeholder_disabled", 40, 12,
           buildPlaceholderDisabledApp)
    runOne("m23_suite_rules", 60, 20,
           buildRulesApp)
    runOne("m23_suite_sparkline", 60, 9,
           portSparkline.buildSparklineApp)
    runOne("m23_suite_progress_gradient", 60, 3,
           buildProgressGradientApp)
    runOne("m23_suite_listview_index", 40, 14,
           buildListViewIndexApp)
    runOne("m23_suite_data_table_row_labels", 80, 14,
           buildDataTableRowLabelsApp)

    check passed >= 8 - TaggedFailures.len
    if failed.len > 0:
      echo "M23 compat suite: failed ports: ", failed
    check failed.len == 0
