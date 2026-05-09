## test_textual_compat_batch2 — M23 Textual Compatibility Suite — Batch 2.
##
## Twelve additional verbatim ports of Textual snapshot apps, building
## on the initial 8 from `test_textual_compat.nim`. Each test mounts
## its port under `TerminalTestHarness`, takes a six-format snapshot,
## and gates the result against a stored golden under
## `tests/snapshots/m23b_<name>/`.
##
## The Batch-2 ports widen the widget surface coverage — Welcome,
## RichLog, Log, OptionList (long), Footer, multi-line / markup
## button labels, viewport-units Static, Checkbox + Label, and a
## horizontal-auto Container.
##
## Tolerance: cell-content identical for plaintext / cellmap / svg
## goldens; the snapshot runner already documents SGR-ordering
## tolerance against Textual's encoder. Per-port fidelity notes:
##
##   - `welcome_widget` — *visually-equivalent*. The default body
##     text is isonim-tui's (the M21 widget ships its own copy);
##     the surrounding chrome is byte-stable.
##   - `button_markup` / `toggle_style_order` —
##     *functionally-equivalent*. Markup brackets render literally
##     because M11/M12 button + checkbox label paths don't yet
##     consume a `Content` value (see README "Found gaps").
##   - `big_button` — *functionally-equivalent*. Textual's
##     `height: 9` CSS isn't yet plumbed through the M12 button
##     widget surface; the rendered button height tracks its label
##     row count.
##   - All other ports are *cell-identical* against the golden
##     once recorded.

import unittest
import isonim_tui

import ../examples/ports/welcome_widget
import ../examples/ports/button_multiline_label
import ../examples/ports/button_markup
import ../examples/ports/option_list_long
import ../examples/ports/big_button
import ../examples/ports/log_write
import ../examples/ports/text_log_blank_write
import ../examples/ports/richlog_max_lines
import ../examples/ports/viewport_units
import ../examples/ports/multi_keys
import ../examples/ports/toggle_style_order
import ../examples/ports/horizontal_auto_width

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

suite "M23: Textual Compatibility Suite — Batch 2 (12 more ports)":

  test "test_compat_welcome_widget":
    snapPort("test_compat_welcome_widget", "m23b_welcome_widget",
             60, 14, buildWelcomeApp)

  test "test_compat_button_multiline_label":
    snapPort("test_compat_button_multiline_label",
             "m23b_button_multiline_label",
             40, 8, buildButtonMultilineLabelApp)

  test "test_compat_button_markup":
    snapPort("test_compat_button_markup", "m23b_button_markup",
             50, 12, buildButtonMarkupApp)

  test "test_compat_option_list_long":
    snapPort("test_compat_option_list_long", "m23b_option_list_long",
             40, 16, buildOptionListLongApp)

  test "test_compat_big_button":
    snapPort("test_compat_big_button", "m23b_big_button",
             40, 10, buildBigButtonApp)

  test "test_compat_log_write":
    snapPort("test_compat_log_write", "m23b_log_write",
             40, 10, buildLogWriteApp)

  test "test_compat_text_log_blank_write":
    snapPort("test_compat_text_log_blank_write",
             "m23b_text_log_blank_write",
             40, 8, buildTextLogBlankWriteApp)

  test "test_compat_richlog_max_lines":
    snapPort("test_compat_richlog_max_lines",
             "m23b_richlog_max_lines",
             40, 8, buildRichLogMaxLinesApp)

  test "test_compat_viewport_units":
    snapPort("test_compat_viewport_units", "m23b_viewport_units",
             40, 6, buildViewportUnitsApp)

  test "test_compat_multi_keys":
    snapPort("test_compat_multi_keys", "m23b_multi_keys",
             40, 3, buildMultiKeysApp)

  test "test_compat_toggle_style_order":
    snapPort("test_compat_toggle_style_order",
             "m23b_toggle_style_order",
             50, 6, buildToggleStyleOrderApp)

  test "test_compat_horizontal_auto_width":
    snapPort("test_compat_horizontal_auto_width",
             "m23b_horizontal_auto_width",
             80, 5, buildHorizontalAutoWidthApp)

  test "test_compat_suite_batch2_12_apps":
    ## Aggregate gate. Mounts every Batch-2 port, snapshots, counts
    ## matches; passes when every non-tagged port matches its golden.
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

    runOne("m23b_suite_welcome_widget", 60, 14,
           buildWelcomeApp)
    runOne("m23b_suite_button_multiline_label", 40, 8,
           buildButtonMultilineLabelApp)
    runOne("m23b_suite_button_markup", 50, 12,
           buildButtonMarkupApp)
    runOne("m23b_suite_option_list_long", 40, 16,
           buildOptionListLongApp)
    runOne("m23b_suite_big_button", 40, 10,
           buildBigButtonApp)
    runOne("m23b_suite_log_write", 40, 10,
           buildLogWriteApp)
    runOne("m23b_suite_text_log_blank_write", 40, 8,
           buildTextLogBlankWriteApp)
    runOne("m23b_suite_richlog_max_lines", 40, 8,
           buildRichLogMaxLinesApp)
    runOne("m23b_suite_viewport_units", 40, 6,
           buildViewportUnitsApp)
    runOne("m23b_suite_multi_keys", 40, 3,
           buildMultiKeysApp)
    runOne("m23b_suite_toggle_style_order", 50, 6,
           buildToggleStyleOrderApp)
    runOne("m23b_suite_horizontal_auto_width", 80, 5,
           buildHorizontalAutoWidthApp)

    check passed >= 12 - TaggedFailures.len
    if failed.len > 0:
      echo "M23 compat suite Batch-2: failed ports: ", failed
    check failed.len == 0
