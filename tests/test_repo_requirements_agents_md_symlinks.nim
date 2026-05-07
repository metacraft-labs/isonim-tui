## test_repo_requirements_agents_md_symlinks
##
## Asserts:
##   * `AGENTS.md` exists.
##   * `CLAUDE.md` is a symlink to `AGENTS.md`.
##   * `.github/copilot-instructions.md` is a symlink to `../AGENTS.md`.
##
## Per `metacraft-specs/policies/repo-requirements.md` §7.

import unittest
import std/os

const repoRoot = currentSourcePath().parentDir().parentDir()

suite "repo requirements: AGENTS.md + symlinks":
  test "test_AGENTS_md_exists":
    check fileExists(repoRoot / "AGENTS.md")

  test "test_CLAUDE_md_symlinks_to_AGENTS_md":
    let claudeMd = repoRoot / "CLAUDE.md"
    check symlinkExists(claudeMd)
    let target = expandSymlink(claudeMd)
    check target == "AGENTS.md"

  test "test_copilot_instructions_symlinks_to_AGENTS_md":
    let copilot = repoRoot / ".github" / "copilot-instructions.md"
    check symlinkExists(copilot)
    let target = expandSymlink(copilot)
    check target == "../AGENTS.md"
