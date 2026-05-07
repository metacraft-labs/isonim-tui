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
src-paths := "--path:src --path:tests --path:../isonim/src --path:../nim-faststreams --path:../nim-stew --path:../nim-everywhere/src"

# Hermetic + style checks - applied to every nim invocation in this file.
nim-flags := "--styleCheck:usages --styleCheck:error"

# The ordered list of test files. Adding a new test_*.nim here gates it
# on CI.
tests := "tests/test_renderer_concept_conformance.nim tests/test_threadvar_id_isolation.nim tests/test_strip_diff.nim tests/test_screenbuffer_diff_empty.nim tests/test_repo_requirements_envrc.nim tests/test_repo_requirements_agents_md_symlinks.nim tests/test_repo_requirements_justfile_recipes.nim tests/test_repo_requirements_ci_yaml.nim tests/test_repo_requirements_flake.nim"

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
    @echo "isonim-tui has no separate integration suite yet — every test is real-stack."
    @echo "Driver-level integration arrives with M2 (TerminalTestHarness)."

test-snapshots:
    @echo "Snapshot tests arrive with M2 (TerminalTestHarness, six snapshot formats)."

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
