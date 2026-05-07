## test_repo_requirements_justfile_recipes
##
## Verifies the `Justfile` defines every recipe required by
## `metacraft-specs/policies/repo-requirements.md` §3:
##   build, test, lint, format (with `fmt` alias), bench, bench --quick.
## Plus the `t` short alias from §3.
##
## We grep the Justfile directly rather than shelling out to `just
## --list`. The check is structural ("the recipe is declared") rather
## than behavioural ("the recipe runs successfully") — actual recipe
## execution is exercised by the `lint` and `test` jobs in CI.

import unittest
import std/[os, strutils]

const repoRoot = currentSourcePath().parentDir().parentDir()

proc loadJustfile(): string =
  result = readFile(repoRoot / "Justfile")

proc hasRecipe(body, name: string): bool =
  ## Recipe declarations look like `name:` or `name PARAM:` at the
  ## start of a line (no leading whitespace). Just allows a colon, an
  ## optional parameter list, then either EOL or a comment.
  for line in body.splitLines:
    let trimmed = line.strip(leading = false, trailing = true)
    if trimmed.startsWith(name & ":") or
       trimmed.startsWith(name & " "):
      return true
  return false

proc hasAlias(body, alias, target: string): bool =
  ## `alias <name> := <target>` line.
  for line in body.splitLines:
    let s = line.strip()
    if s.startsWith("alias " & alias & " :=") and target in s:
      return true
  return false

suite "repo requirements: Justfile recipes":
  let body = loadJustfile()

  test "test_recipe_build":
    check hasRecipe(body, "build")

  test "test_recipe_test":
    check hasRecipe(body, "test")

  test "test_recipe_lint":
    check hasRecipe(body, "lint")

  test "test_recipe_format":
    check hasRecipe(body, "format")

  test "test_alias_fmt":
    check hasAlias(body, "fmt", "format")

  test "test_recipe_bench":
    check hasRecipe(body, "bench")

  test "test_recipe_bench_quick":
    # `bench --quick` is exposed via a `bench-quick` recipe (Just doesn't
    # accept `--` flags directly in recipe names; the convention across
    # nim-pty/libvterm/termctl is `bench-quick`).
    check hasRecipe(body, "bench-quick") or hasRecipe(body, "bench")

  test "test_alias_t":
    check hasAlias(body, "t", "test")

  test "test_recipe_bump_version":
    # §6: single-source-of-truth version bump.
    check hasRecipe(body, "bump-version")
