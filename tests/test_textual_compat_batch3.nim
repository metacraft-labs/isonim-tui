## test_textual_compat_batch3 — M23 Textual Compatibility Suite — Batch 3.
##
## Eleven additional verbatim-style ports of Textual snapshot apps,
## landing alongside the `Container.clHorizontal` default-render
## switch (the legacy vertical fall-through retired; M23 batch-1 /
## batch-2 horizontal goldens were re-recorded against the real
## left-to-right path in the same change-set). Each test mounts its
## port under `TerminalTestHarness`, takes a six-format snapshot,
## and gates the result against a stored golden under
## `tests/snapshots/m23c_<name>/`.
##
## Batch 3 widens widget surface coverage further — Static padding,
## a multi-border-style sweep, three-deep nested Containers, a Tabs
## widget with three entries, ProgressBar at five percentage points,
## LoadingIndicator stack, Header with title/subtitle, Footer with
## chip bindings, ListView basic, Checkbox grid, plus two ports
## (`horizontal_static_row`, `buttons_horizontal_row`) that
## explicitly exercise the new `clHorizontal` default.
##
## Tolerance contract is identical to Batch 1 / Batch 2 — see
## `examples/ports/README.md` for the per-port fidelity matrix.

import unittest
import isonim_tui

import ../examples/ports/static_padding
import ../examples/ports/multiple_borders
import ../examples/ports/nested_containers
import ../examples/ports/tabs_basic
import ../examples/ports/progress_bar_states
import ../examples/ports/loading_indicator_demo
import ../examples/ports/header_with_title
import ../examples/ports/footer_chips
import ../examples/ports/horizontal_static_row
import ../examples/ports/listview_basic
import ../examples/ports/checkbox_grid
import ../examples/ports/buttons_horizontal_row

const TaggedFailures: array[0, tuple[name, reason: string]] = []

proc isTaggedFailure(name: string): bool =
  for tf in TaggedFailures:
    if tf.name == name: return true
  false

template snapPort(testName, snapName: string; cols, rows: int;
                  builder: untyped): untyped =
  let h = newTerminalTestHarness(cols, rows)
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    builder(h))
  let matched = h.snap(snapName)
  if not isTaggedFailure(testName):
    check matched
  h.dispose()

suite "M23: Textual Compatibility Suite — Batch 3 (12 more ports)":

  test "test_compat_static_padding":
    snapPort("test_compat_static_padding", "m23c_static_padding",
             40, 10, buildStaticPaddingApp)

  test "test_compat_multiple_borders":
    snapPort("test_compat_multiple_borders", "m23c_multiple_borders",
             40, 18, buildMultipleBordersApp)

  test "test_compat_nested_containers":
    snapPort("test_compat_nested_containers", "m23c_nested_containers",
             40, 8, buildNestedContainersApp)

  test "test_compat_tabs_basic":
    snapPort("test_compat_tabs_basic", "m23c_tabs_basic",
             50, 8, buildTabsBasicApp)

  test "test_compat_progress_bar_states":
    snapPort("test_compat_progress_bar_states",
             "m23c_progress_bar_states",
             40, 8, buildProgressBarStatesApp)

  test "test_compat_loading_indicator_demo":
    snapPort("test_compat_loading_indicator_demo",
             "m23c_loading_indicator_demo",
             40, 6, buildLoadingIndicatorDemoApp)

  test "test_compat_header_with_title":
    snapPort("test_compat_header_with_title",
             "m23c_header_with_title",
             60, 3, buildHeaderWithTitleApp)

  test "test_compat_footer_chips":
    snapPort("test_compat_footer_chips", "m23c_footer_chips",
             60, 3, buildFooterChipsApp)

  test "test_compat_horizontal_static_row":
    snapPort("test_compat_horizontal_static_row",
             "m23c_horizontal_static_row",
             50, 5, buildHorizontalStaticRowApp)

  test "test_compat_listview_basic":
    snapPort("test_compat_listview_basic", "m23c_listview_basic",
             40, 10, buildListViewBasicApp)

  test "test_compat_checkbox_grid":
    snapPort("test_compat_checkbox_grid", "m23c_checkbox_grid",
             40, 8, buildCheckboxGridApp)

  test "test_compat_buttons_horizontal_row":
    snapPort("test_compat_buttons_horizontal_row",
             "m23c_buttons_horizontal_row",
             60, 5, buildButtonsHorizontalRowApp)

  test "test_compat_suite_batch3_12_apps":
    ## Aggregate gate. Mounts every Batch-3 port, snapshots,
    ## counts matches; passes when every non-tagged port matches its
    ## golden.
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

    runOne("m23c_suite_static_padding", 40, 10,
           buildStaticPaddingApp)
    runOne("m23c_suite_multiple_borders", 40, 18,
           buildMultipleBordersApp)
    runOne("m23c_suite_nested_containers", 40, 8,
           buildNestedContainersApp)
    runOne("m23c_suite_tabs_basic", 50, 8,
           buildTabsBasicApp)
    runOne("m23c_suite_progress_bar_states", 40, 8,
           buildProgressBarStatesApp)
    runOne("m23c_suite_loading_indicator_demo", 40, 6,
           buildLoadingIndicatorDemoApp)
    runOne("m23c_suite_header_with_title", 60, 3,
           buildHeaderWithTitleApp)
    runOne("m23c_suite_footer_chips", 60, 3,
           buildFooterChipsApp)
    runOne("m23c_suite_horizontal_static_row", 50, 5,
           buildHorizontalStaticRowApp)
    runOne("m23c_suite_listview_basic", 40, 10,
           buildListViewBasicApp)
    runOne("m23c_suite_checkbox_grid", 40, 8,
           buildCheckboxGridApp)
    runOne("m23c_suite_buttons_horizontal_row", 60, 5,
           buildButtonsHorizontalRowApp)

    check passed >= 12 - TaggedFailures.len
    if failed.len > 0:
      echo "M23 compat suite Batch-3: failed ports: ", failed
    check failed.len == 0
