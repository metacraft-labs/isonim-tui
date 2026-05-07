## test_repo_requirements_envrc
##
## Asserts the `.envrc` at the repo root contains `use flake`, per
## `metacraft-specs/policies/repo-requirements.md` §2 (direnv).

import unittest
import std/[os, strutils]

const repoRoot = currentSourcePath().parentDir().parentDir()

suite "repo requirements: .envrc":
  test "test_envrc_exists":
    check fileExists(repoRoot / ".envrc")

  test "test_envrc_contains_use_flake":
    let body = readFile(repoRoot / ".envrc")
    check "use flake" in body
