## test_repo_requirements_agents_md_symlinks
##
## Asserts:
##   * `AGENTS.md` exists.
##   * `CLAUDE.md` does NOT exist (not even as a dangling symlink): Claude
##     Code reads `AGENTS.md` itself and a `CLAUDE.md` shadows it.
##   * `.github/copilot-instructions.md` is a symlink to `../AGENTS.md`.
##
## Per `metacraft-specs/policies/repo-requirements.md` §7.

import unittest
import std/os

const repoRoot = currentSourcePath().parentDir().parentDir()

suite "repo requirements: AGENTS.md + symlinks":
  test "test_AGENTS_md_exists":
    check fileExists(repoRoot / "AGENTS.md")

  test "test_CLAUDE_md_is_absent":
    # On Windows with core.symlinks=false the old CLAUDE.md -> AGENTS.md
    # symlink was checked out as a file holding the single word "AGENTS.md",
    # which is all a Claude Code session there then saw. `symlinkExists` is
    # checked as well as `fileExists` so a dangling symlink is still caught.
    let claudeMd = repoRoot / "CLAUDE.md"
    check not fileExists(claudeMd)
    check not symlinkExists(claudeMd)

  test "test_copilot_instructions_symlinks_to_AGENTS_md":
    let copilot = repoRoot / ".github" / "copilot-instructions.md"
    check symlinkExists(copilot)
    let target = expandSymlink(copilot)
    check target == "../AGENTS.md"
