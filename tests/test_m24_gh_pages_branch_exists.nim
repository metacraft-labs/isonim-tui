## test_m24_gh_pages_branch_exists
##
## Smoke test for the M24 (Continuous Benchmarking) gh-pages baseline
## store. The CI workflow `.github/workflows/benchmark.yml` writes one
## datapoint per main-branch run via
## `benchmark-action/github-action-benchmark@v1`, configured with:
##
##   gh-pages-branch:          gh-pages
##   benchmark-data-dir-path:  perf/bench
##
## For the very first main-branch run to succeed without falling back to
## the workflow's "Ensure gh-pages baseline branch exists" bootstrap
## step, the branch must already exist locally with the right shape.
## This test asserts:
##
##   1. `gh-pages` branch exists in the local repository.
##   2. `gh-pages:perf/bench/` exists (matches workflow path).
##   3. `gh-pages:.nojekyll` exists (so GitHub Pages serves files like
##      `_data/`, which github-action-benchmark writes).
##
## We invoke real `git` via `osproc` — no fakes, no fixtures — per the
## charter's no-mocks rule.
##
## Note: We skip when running outside a git checkout (e.g. an extracted
## tarball release). We do not skip when the branch is missing — that
## is the failure mode this test exists to catch.

import unittest
import std/[os, osproc, strutils]

const repoRoot = currentSourcePath().parentDir().parentDir()

proc git(args: varargs[string]): tuple[output: string, code: int] =
  ## Runs `git` in the repo root. Returns trimmed stdout/stderr combined
  ## and the exit code. We use `execCmdEx` rather than `startProcess`
  ## directly because the resulting tuple matches what we want to assert
  ## against without further plumbing.
  var cmd = "git -C " & quoteShell(repoRoot)
  for a in args:
    cmd.add ' '
    cmd.add quoteShell(a)
  let (raw, code) = execCmdEx(cmd)
  result = (raw.strip(), code)

suite "M24: gh-pages baseline branch":
  test "test_repo_is_a_git_checkout":
    let (_, code) = git("rev-parse", "--is-inside-work-tree")
    check code == 0

  test "test_gh_pages_branch_exists_locally":
    ## `git show-ref --verify` exits 0 iff the ref exists.
    let (_, code) = git("show-ref", "--verify", "--quiet",
                        "refs/heads/gh-pages")
    check code == 0

  test "test_gh_pages_perf_bench_dir_exists":
    ## `git ls-tree gh-pages -- perf/bench` lists the tree entry; an
    ## empty result means the path doesn't exist on that branch.
    let (output, code) = git("ls-tree", "gh-pages", "--", "perf/bench")
    check code == 0
    check output.len > 0
    ## The entry is a tree (a directory), not a blob.
    check "tree" in output

  test "test_gh_pages_nojekyll_exists":
    ## `.nojekyll` tells GitHub Pages not to run Jekyll, which would
    ## otherwise hide files like `_data/` that github-action-benchmark
    ## writes underneath `perf/bench/`.
    let (output, code) = git("ls-tree", "gh-pages", "--", ".nojekyll")
    check code == 0
    check output.len > 0
    check "blob" in output

  test "test_workflow_paths_match_branch_layout":
    ## Cross-check: the paths the smoke test asserts on must match the
    ## workflow's configuration. If someone moves the data directory in
    ## `benchmark.yml` without updating gh-pages, we want this test to
    ## flag the divergence.
    let body = readFile(repoRoot / ".github" / "workflows" / "benchmark.yml")
    check "gh-pages-branch: gh-pages" in body
    check "benchmark-data-dir-path: perf/bench" in body
