## test_repo_requirements_ci_yaml
##
## Verifies `.github/workflows/ci.yml` declares at minimum the
## `test`, `lint`, and `nix-build` jobs, which the organisation's repository
## requirements ask of every repo, that no step uses an inline multi-line
## bash block (logic belongs in a Justfile recipe or a script, where it can be
## run and reviewed locally), and that every job in every workflow sets
## `timeout-minutes` (a hung job on a scarce runner class otherwise holds it
## for GitHub's 6-hour default; a macOS test hang once held every macOS runner
## that long).
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
    ## `run: |` followed by a multi-line block is not allowed unless the
    ## block is a single `just <target>` invocation: logic in a workflow
    ## cannot be run or reviewed locally. We approximate this by asserting
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

proc jobsWithoutTimeout(workflow: string): tuple[jobs, missing: seq[string]] =
  ## Names of the jobs in `workflow` (a file under .github/workflows) whose
  ## block has no `timeout-minutes:` line. A job header is a two-space
  ## indented key under the top-level `jobs:`; its block runs to the next
  ## header or the end of the file.
  var inJobs = false
  var current = ""
  var hasTimeout = false
  for line in readFile(repoRoot / ".github" / "workflows" / workflow).splitLines:
    if line.startsWith("jobs:"):
      inJobs = true
      continue
    if not inJobs: continue
    if line.len > 0 and line[0] != ' ' and line[0] != '#':
      break  # another top-level key ends `jobs:`
    if line.len > 3 and line.startsWith("  ") and line[2] notin {' ', '#'} and
        line.strip.endsWith(":"):
      if current.len > 0 and not hasTimeout: result.missing.add current
      current = line.strip.strip(chars = {':'})
      result.jobs.add current
      hasTimeout = false
    elif line.startsWith("    timeout-minutes:"):
      hasTimeout = true
  if current.len > 0 and not hasTimeout: result.missing.add current

suite "repo requirements: every workflow job sets timeout-minutes":
  for wf in ["ci.yml", "ci-reprobuild.yml", "benchmark.yml"]:
    test "test_timeout_minutes_on_every_job_" & wf:
      let (jobs, missing) = jobsWithoutTimeout(wf)
      checkpoint wf & ": jobs " & $jobs & "; without timeout-minutes: " & $missing
      # A parse that found no job would pass vacuously.
      check jobs.len > 0
      check missing.len == 0

