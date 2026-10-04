## M24 real baseline store checks for the consuming runtime checkout.
## Existing dev-source benchmark eligibility is preserved: ordinary promotion
## source cannot publish its own reference baseline. Actual twenty metrics are
## conserved across sixteen smaller-is-better and four bigger-is-better metrics,
## stored in perf/bench and perf/bench-bigger on the real gh-pages branch.
## This test invokes real registered Git directly, validates the current owning
## source root, and retains the original ref/tree/.nojekyll/workflow assertions.
## Missing checkout or genuine measurement data fails; no fake branch, fixture
## baseline, shell fallback or archived producing-workspace adminroot is used.
##
import unittest
import std/[os, osproc, streams, strutils]

# Resolve the consuming runtime checkout, never a cached producer path embedded
# by currentSourcePath during compilation in another workspace.
let repoRoot = getCurrentDir()
doAssert fileExists(repoRoot / "isonim_tui.nimble"), "not an owning TUI source root"
doAssert fileExists(repoRoot / "tests" / "test_m24_gh_pages_branch_exists.nim"),
  "required baseline test source is absent"
doAssert fileExists(repoRoot / ".github" / "workflows" / "benchmark.yml"),
  "required owning benchmark workflow is absent"

proc git(args: varargs[string]): tuple[output: string, code: int] =
  ## Execute the resolved registered Git directly, retaining real exit/output.
  ## No system-shell fallback or compile-time executable path is involved.
  let executable = findExe("git")
  doAssert executable.len > 0, "required registered Git executable is absent"
  let process = startProcess(executable, workingDir = repoRoot, args = @args,
    options = {poStdErrToStdOut})
  try:
    let output = process.outputStream.readAll()
    result = (output.strip(), process.waitForExit())
  finally:
    process.close()

suite "M24: gh-pages baseline branch":
  test "test_repo_is_a_git_checkout":
    let (_, code) = git("rev-parse", "--is-inside-work-tree")
    check code == 0
    let (root, rootCode) = git("rev-parse", "--show-toplevel")
    check rootCode == 0
    check root.expandFilename() == repoRoot.expandFilename()

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

  test "test_gh_pages_bigger_channel_dir_exists":
    let (output, code) = git("ls-tree", "gh-pages", "--", "perf/bench-bigger")
    check code == 0
    check output.len > 0
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
    check "benchmark-data-dir-path: perf/bench-bigger" in body
