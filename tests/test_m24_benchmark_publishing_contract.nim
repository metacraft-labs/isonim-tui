## test_m24_benchmark_publishing_contract — where benchmark numbers may
## come from.
##
## A benchmark result is only worth keeping if it was measured without other
## work on the machine. isonim-tui therefore stores and publishes results
## (the PR comparison comment, and the gh-pages baseline in its two channels
## `perf/bench` and `perf/bench-bigger`) only from the CPU-isolated,
## single-tenant benchmark runner, selected by
## `[linux, x64, benchmark-isolated]`. Shared runners may run the suite as a
## pass/fail threshold gate and nothing more. This test reads
## `.github/workflows/benchmark.yml` and checks that contract:
##
##   * every job that touches gh-pages, runs github-action-benchmark or
##     pushes runs on exactly `[linux, x64, benchmark-isolated]`;
##   * that job publishes both channels to gh-pages;
##   * no job creates gh-pages (an orphan branch made on a shared runner is
##     how an unmeasured baseline would start);
##   * every other job that runs the suite gates on the hard thresholds and
##     holds no write permission.
##
## It does not check whether gh-pages already holds data on the remote. That
## is a fact about the remote, not about this source tree: the branch holds
## no measurement until the first isolated run on `dev` publishes one, and a
## checkout made by CI has no local gh-pages ref either way.
##
## MOCK POLICY: no mocks. The test reads the committed workflow file. It
## matches YAML structurally (job headers at two spaces of indentation under
## `jobs:`) instead of parsing it, because the dev shell carries no YAML
## library and the workflow is written in that one shape; a job written in
## another shape fails `test_jobs_were_found` rather than passing unseen.

import unittest
import std/[os, strutils, tables]

# The checkout the test runs in, not the one it was compiled in: a cached
# binary may have been built in another workspace.
let repoRoot = getCurrentDir()
doAssert fileExists(repoRoot / "isonim_tui.nimble"),
  "run from the isonim-tui checkout root"
let workflowPath = repoRoot / ".github" / "workflows" / "benchmark.yml"
const isolatedRunsOn = "[linux, x64, benchmark-isolated]"

type Job = object
  name: string
  runsOn: string
  body: string

proc parseJobs(text: string): OrderedTable[string, Job] =
  ## Splits the `jobs:` mapping into one entry per job. A job header is a
  ## line of the form `  <name>:`; its body runs to the next header.
  result = initOrderedTable[string, Job]()
  var inJobs = false
  var current = ""
  for line in text.splitLines():
    if line == "jobs:":
      inJobs = true
      continue
    if not inJobs: continue
    if line.len > 0 and not line.startsWith(" ") and not line.startsWith("#"):
      break                      # a later top-level key ends `jobs:`
    if line.startsWith("  ") and not line.startsWith("   ") and
        line.strip().endsWith(":") and not line.strip().startsWith("#"):
      current = line.strip()[0 ..< ^1]
      result[current] = Job(name: current)
      continue
    if current.len == 0: continue
    let stripped = line.strip()
    if line.startsWith("    runs-on:") and not line.startsWith("     "):
      result[current].runsOn = stripped["runs-on:".len .. ^1].strip()
    if not stripped.startsWith("#"):
      result[current].body.add stripped & "\n"

proc publishes(job: Job): bool =
  ## Any of these makes a job a producer of stored or published results.
  for marker in ["gh-pages", "github-action-benchmark", "git push",
                 " push origin", "auto-push: true", "comment-always"]:
    if marker in job.body: return true

let jobs = parseJobs(readFile(workflowPath))

suite "M24: benchmark publishing contract":
  test "test_jobs_were_found":
    check jobs.len >= 2
    for job in jobs.values:
      check job.runsOn.len > 0

  test "test_publishing_jobs_run_only_on_isolated_runner":
    var publishers = 0
    for job in jobs.values:
      if job.publishes:
        inc publishers
        checkpoint job.name & " publishes but runs on " & job.runsOn
        check job.runsOn == isolatedRunsOn
    check publishers >= 1

  test "test_isolated_job_publishes_both_channels":
    var found = false
    for job in jobs.values:
      if job.runsOn != isolatedRunsOn: continue
      if "gh-pages-branch: gh-pages" notin job.body: continue
      found = true
      check "benchmark-data-dir-path: perf/bench\n" in job.body
      check "benchmark-data-dir-path: perf/bench-bigger\n" in job.body
      check "push origin gh-pages:gh-pages" in job.body
      # PR comparisons never push.
      check "auto-push: true" notin job.body
    check found

  test "test_no_job_creates_gh_pages":
    for job in jobs.values:
      checkpoint job.name
      check "--orphan" notin job.body
      check "checkout -b gh-pages" notin job.body
      check "switch -c gh-pages" notin job.body

  test "test_shared_runner_jobs_gate_only":
    var gates = 0
    for job in jobs.values:
      if job.runsOn == isolatedRunsOn: continue
      if "just bench" notin job.body: continue
      inc gates
      checkpoint job.name
      check not job.publishes
      check "check-hard-thresholds.sh" in job.body
      check "contents: read" in job.body
    check gates >= 1
