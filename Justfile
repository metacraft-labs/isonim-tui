## Justfile - isonim-tui.
##
## Recipe taxonomy mirrors the L1-L3 sibling repos
## (nim-pty / nim-libvterm / nim-termctl):
##
##   * Top-level aggregates: `build`, `test`, `lint`, `format` / `fmt`.
##   * `test` runs the *default* matrix point (orc + release + threads:on)
##     for fast iteration. The full charter matrix lives under `test-all`
##     and the per-axis recipes (`test-arc`, `test-asan`, etc.) — those
##     are what CI invokes per matrix cell.
##   * Hermetic flags (`--skipParentCfg --skipUserCfg`) are baked into
##     `nim-flags` so every invocation gets the same isolation.

alias t := test
alias fmt := format

# Path lookups - mirrors what `config.nims` exports (kept here so a
# developer running `just <recipe>` outside direnv still resolves
# sibling-repo sources).
src-paths := "--path:src --path:tests --path:../isonim/src --path:../nim-termctl/src --path:../nim-pty/src --path:../nim-faststreams --path:../nim-stew --path:../nim-everywhere/src"

# Hermetic + style checks - applied to every nim invocation in this file.
nim-flags := "--styleCheck:usages --styleCheck:error"

# The ordered list of test files. Adding a new test_*.nim here gates it
# on CI.
tests := "tests/test_renderer_concept_conformance.nim tests/test_threadvar_id_isolation.nim tests/test_strip_diff.nim tests/test_screenbuffer_diff_empty.nim tests/test_repo_requirements_envrc.nim tests/test_repo_requirements_agents_md_symlinks.nim tests/test_repo_requirements_justfile_recipes.nim tests/test_repo_requirements_ci_yaml.nim tests/test_repo_requirements_flake.nim tests/test_grapheme_cluster_corpus.nim tests/test_grapheme_width_emoji_zwj.nim tests/test_sgr_minimal_transition.nim tests/test_sgr_truecolor.nim tests/test_content_word_wrap_grapheme_aware.nim tests/test_ambiguous_width_default_narrow.nim tests/test_content_basics.nim tests/test_headless_capture_static_real_stack.nim tests/test_harness_isolation_parallel.nim tests/test_pilot_press_full_chain.nim tests/test_pilot_type_emits_per_character_events.nim tests/test_pilot_waitfor_uses_virtual_clock.nim tests/test_findbyid_and_dumptree.nim tests/test_eventlog_records_in_order.nim tests/test_snapshot_six_formats_recorded.nim tests/test_snapshot_html_report_on_failure.nim tests/test_snapshot_record_mode.nim tests/test_snapshot_stable_across_runs.nim tests/test_layout_cell_snap_integer_real_yoga.nim tests/test_layout_cell_snap_distributes_error.nim tests/test_layout_grid_three_columns_with_gap.nim tests/test_dock_pinned_left.nim tests/test_double_width_text_reserved_correctly.nim tests/test_layout_reflow_delta.nim tests/test_layout_engine_shared_with_cocoa.nim tests/test_input_simple_keys_corpus.nim tests/test_input_mouse_sgr_corpus.nim tests/test_input_partial_sequence.nim tests/test_input_bracketed_paste.nim tests/test_input_kitty_protocol.nim tests/test_input_in_band_resize.nim tests/test_input_reissue_on_overlength.nim tests/test_css_tokenize_real_textual_corpus.nim tests/test_css_parse_real_textual_corpus.nim tests/test_css_match_specificity_corpus.nim tests/test_css_cascade_full_chain.nim tests/test_css_pseudo_state_focus_repaints.nim tests/test_css_styles_cache_invalidation.nim tests/test_css_tailwind_compat.nim tests/test_css_error_recovery.nim tests/test_color_parse_corpus.nim tests/test_color_blend_gamma_correct.nim tests/test_colorsystem_luminosity_spread.nim tests/test_textual_dark_byte_identical.nim tests/test_runtime_theme_switch.nim tests/test_at_dark_at_light_full_app.nim tests/test_isonim_theme_token_compat.nim tests/test_easing_byte_parity.nim tests/test_animator_full_chain.nim tests/test_animation_cancellation.nim tests/test_animation_pilot_wait_for_animation.nim tests/test_color_blend_in_animation.nim tests/test_compositor_idle_no_writes.nim tests/test_compositor_single_cell_diff.nim tests/test_compositor_overlay_layer.nim tests/test_compositor_strip_cache_hit.nim tests/test_segment_dedup.nim tests/test_posix_driver_real_pty.nim tests/test_posix_driver_resize_real.nim tests/test_posix_driver_mouse_real.nim tests/test_posix_driver_panic_restores_terminal.nim tests/test_posix_driver_sigterm_clean_exit.nim tests/test_windows_driver_keys_round_trip.nim tests/test_windows_driver_resize.nim tests/test_widget_set_snapshot_windows.nim tests/test_windows_driver_ctrl_c_clean_exit.nim tests/test_static_borders_real_cells.nim tests/test_label_rich_text_wraps.nim tests/test_container_scroll_keyboard.nim tests/test_placeholder_widget.nim tests/test_rule_widget.nim tests/test_m11_widget_snapshot_coverage.nim tests/test_button_activate_with_enter.nim tests/test_focus_tab_order.nim tests/test_switch_keyboard_toggle.nim tests/test_radio_set_exclusive.nim tests/test_m12_introspection_per_widget.nim tests/test_m12_widget_snapshot_coverage.nim tests/test_listview_keyboard_navigation.nim tests/test_modal_focus_trap_real.nim tests/test_modal_animation_frames.nim tests/test_select_dropdown_keyboard.nim tests/test_collapsible_animation.nim tests/test_toast_autodismiss.nim tests/test_image_widget_kitty.nim tests/test_image_widget_protocol_fallback.nim tests/test_image_widget_hot_reload.nim tests/test_worker_runs_to_completion.nim tests/test_worker_cancellation.nim tests/test_workers_isolated_per_harness.nim tests/test_fuzzy_matcher_corpus.nim tests/test_palette_open_search_run.nim tests/test_datatable_virtualisation_perf.nim tests/test_datatable_sort_keyboard.nim tests/test_datatable_selection.nim tests/test_datatable_snapshot_coverage.nim tests/test_tree_expand_lazy.nim tests/test_directory_tree_real_fs.nim tests/test_tree_snapshot_coverage.nim tests/test_textarea_undo_redo.nim tests/test_textarea_syntax_highlighting.nim tests/test_textarea_word_wrap_grapheme_aware.nim"

# --- Default targets (per repo-requirements.md) ---

# Build: compile every test file as a sanity check (no run).
build:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "Building $t"; \
      nim c {{nim-flags}} {{src-paths}} --mm:orc -d:release --threads:on \
          -o:test-logs/$(basename $t .nim) $t 2>&1 | tee -a test-logs/build.log; \
    done

# Test: run the default matrix point (orc + release + threads:on).
test: test-orc

# Sub-recipes (verb-noun pattern). Required by §3 of repo-requirements.
test-unit: test-orc

test-integration:
    @echo "isonim-tui has no separate integration suite — every test is real-stack."
    @echo "M2 added the TerminalTestHarness suite (driver/pilot/snapshot tests)."

test-snapshots:
    @mkdir -p test-logs
    @for t in tests/test_snapshot_six_formats_recorded.nim tests/test_snapshot_html_report_on_failure.nim tests/test_snapshot_record_mode.nim tests/test_snapshot_stable_across_runs.nim; do \
      echo "[snap] $t"; \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:orc -d:release --threads:on \
        -r $t 2>&1 | tee -a test-logs/snapshots.log; \
    done

# Lint: nim check + nixfmt --check + markdownlint.
lint: lint-nim lint-nix lint-markdown

lint-nim:
    @mkdir -p test-logs
    nim check {{nim-flags}} {{src-paths}} --mm:orc src/isonim_tui.nim 2>&1 | tee test-logs/lint-nim.log
    @for t in {{tests}}; do \
      echo "Checking $t"; \
      nim check {{nim-flags}} {{src-paths}} --mm:orc --threads:on $t 2>&1 | tee -a test-logs/lint-nim.log; \
    done

lint-nix:
    nixfmt --check flake.nix

lint-markdown:
    @if command -v markdownlint-cli2 >/dev/null 2>&1; then \
      markdownlint-cli2 "**/*.md" "#node_modules" "#test-logs" || true; \
    else \
      echo "markdownlint-cli2 not available; skipping"; \
    fi

format: format-nim format-nix

format-nim:
    @if command -v nimpretty >/dev/null 2>&1; then \
      nimpretty src/isonim_tui.nim src/isonim_tui/*.nim tests/*.nim; \
    else \
      echo "nimpretty not available; skipping Nim formatting"; \
    fi

format-nix:
    nixfmt flake.nix

# Single-source-of-truth version bump (§6).
bump-version version:
    sed -i 's/^version[[:space:]]*=.*/version       = "{{version}}"/' isonim_tui.nimble

# --- Charter matrix (memory managers x compile modes x threading) ---
#
# Each `test-<axis>` recipe runs the full test list under one configuration.
# CI runs them in parallel via the matrix in .github/workflows/ci.yml.

test-arc:
    just _matrix arc release on
    just _matrix arc debug on
    just _matrix arc danger on

test-orc:
    just _matrix orc release on
    just _matrix orc debug on
    just _matrix orc danger on

test-refc:
    just _matrix refc release on
    just _matrix refc debug on
    just _matrix refc danger on

test-threads-off:
    just _matrix orc release off
    just _matrix arc release off

# Sanitizers (Linux/amd64 only).
test-asan:
    @mkdir -p test-logs
    @for mode in release danger; do \
      for t in {{tests}}; do \
        echo "[asan/$mode] $t"; \
        CC=clang CXX=clang++ \
        nim c {{nim-flags}} {{src-paths}} \
          --mm:orc -d:$mode -d:useMalloc --threads:on \
          --cc:clang \
          --passC:-fsanitize=address --passL:-fsanitize=address \
          --debugger:native \
          -r $t 2>&1 | tee -a test-logs/asan-$mode.log; \
      done; \
    done

test-ubsan:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[ubsan] $t"; \
      CC=clang CXX=clang++ \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:orc -d:release -d:useMalloc --threads:on \
        --cc:clang \
        --passC:-fsanitize=undefined --passL:-fsanitize=undefined \
        -r $t 2>&1 | tee -a test-logs/ubsan.log; \
    done

test-tsan:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[tsan] $t"; \
      CC=clang CXX=clang++ \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:orc -d:release -d:useMalloc --threads:on \
        --cc:clang \
        --passC:-fsanitize=thread --passL:-fsanitize=thread \
        -r $t 2>&1 | tee -a test-logs/tsan.log; \
    done

test-lsan:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[lsan] $t"; \
      CC=clang CXX=clang++ \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:orc -d:release -d:useMalloc --threads:on \
        --cc:clang \
        --passC:-fsanitize=leak --passL:-fsanitize=leak \
        -r $t 2>&1 | tee -a test-logs/lsan.log; \
    done

test-valgrind:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p test-logs
    for t in {{tests}}; do
      out=test-logs/valgrind-$(basename $t .nim)
      echo "[valgrind] $t"
      nim c {{nim-flags}} {{src-paths}} \
        --mm:orc -d:release -d:useMalloc --threads:on \
        --debugger:native \
        -o:$out $t 2>&1 | tee -a test-logs/valgrind.log
      valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 \
        --child-silent-after-fork=yes \
        $out 2>&1 | tee -a test-logs/valgrind.log
      ec=${PIPESTATUS[0]}
      if [ $ec -ne 0 ]; then
        echo "valgrind reported errors for $t (exit=$ec)"
        exit $ec
      fi
    done

test-all: test-arc test-orc test-refc test-threads-off
    @echo "Charter primary matrix complete."

# Internal: one matrix cell.  $1=mm, $2=mode, $3=threads
_matrix mm mode threads:
    @mkdir -p test-logs
    @for t in {{tests}}; do \
      echo "[{{mm}}/{{mode}}/threads:{{threads}}] $t"; \
      nim c {{nim-flags}} {{src-paths}} \
        --mm:{{mm}} -d:{{mode}} --threads:{{threads}} \
        -r $t 2>&1 | tee -a test-logs/{{mm}}-{{mode}}-threads-{{threads}}.log; \
    done

# Clean test-logs and nim caches.
clean:
    rm -rf test-logs nim-cache
    find tests -maxdepth 1 -type f -executable -name "test_*" -not -name "*.nim" -delete

# --- Benchmarks ---
#
# Per `metacraft-specs/policies/continuous-benchmarking.md` the recipes
# must exist at M0; the actual suite content lands at M24. Until then
# the recipes print a clear "deferred" message so CI doesn't
# false-positive.

bench:
    @echo "isonim-tui benchmark suite lands with M24."
    @echo "M0 ships the recipe (and bench-quick) so the conformance check passes."
    @mkdir -p bench-results
    @echo '{"placeholder": true, "milestone": "M24"}' > bench-results/benchmark_results.json

bench-quick:
    @echo "isonim-tui --quick benchmark suite lands with M24."
    @mkdir -p bench-results
    @echo '{"placeholder": true, "milestone": "M24", "quick": true}' > bench-results/benchmark_results.json
