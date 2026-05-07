## test_repo_requirements_ci_yaml
##
## Verifies `.github/workflows/ci.yml` declares at minimum the
## `test`, `lint`, and `nix-build` jobs (per
## `metacraft-specs/policies/repo-requirements.md` §5), and that no
## step uses an inline multi-line bash block (per
## `metacraft-specs/policies/ci-workflow-standards.md`).
##
## We do not rely on `yq` (not always installed in the dev shell);
## a structural string-search is precise enough for the gating
## requirement and produces a useful failure message.

import unittest
import std/[os, strutils]

const repoRoot = currentSourcePath().parentDir().parentDir()

proc loadCi(): string =
  readFile(repoRoot / ".github" / "workflows" / "ci.yml")

suite "repo requirements: ci.yml":
  let body = loadCi()

  test "test_ci_job_test_declared":
    # Job header looks like `  test:` at indent 2.
    check "  test:" in body or "  Test:" in body

  test "test_ci_job_lint_declared":
    check "  lint:" in body or "  Lint:" in body

  test "test_ci_job_nix_build_declared":
    check "  nix-build:" in body

  test "test_ci_no_inline_multiline_run":
    ## `run: |` followed by a multi-line block is forbidden by
    ## ci-workflow-standards.md unless the block is a single
    ## `just <target>` invocation. We approximate this by asserting
    ## that no `run: |` line appears at all — every existing run uses
    ## the inline `run: just …` form, which is the canonical way to
    ## conform to the standard.
    for line in body.splitLines:
      let s = line.strip(leading = true, trailing = true)
      check not s.startsWith("run: |")

  test "test_ci_artifacts_uploaded_on_always":
    ## §5: full log preservation as artifacts via `if: always()`.
    check "if: always()" in body
    check "actions/upload-artifact" in body
