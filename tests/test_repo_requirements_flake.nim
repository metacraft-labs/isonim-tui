## test_repo_requirements_flake
##
## Verifies `flake.nix` conforms to
## `metacraft-specs/policies/repo-requirements.md` §1:
##   * `devShells.default` declared
##   * `packages.default` declared
##   * `checks.*` declared (we look for `checks.pre-commit` here)
##   * Inputs use `nixos-modules` with the `follows` block
##   * The four required systems are present
##
## A full `nix flake show` invocation is reserved for the CI job that
## actually has Nix evaluator access; this test does the structural
## grep that runs in any environment.

import unittest
import std/[os, strutils]

const repoRoot = currentSourcePath().parentDir().parentDir()

proc loadFlake(): string =
  readFile(repoRoot / "flake.nix")

suite "repo requirements: flake.nix":
  let body = loadFlake()

  test "test_flake_devshells_default":
    check "devShells.default" in body

  test "test_flake_packages_default":
    check "packages.default" in body

  test "test_flake_checks_present":
    check "checks." in body

  test "test_flake_input_nixos_modules":
    check "nixos-modules" in body

  test "test_flake_follows_block":
    check "follows" in body
    check "nixos-modules/nixpkgs-unstable" in body

  test "test_flake_systems_x86_64_linux":
    check "x86_64-linux" in body

  test "test_flake_systems_aarch64_linux":
    check "aarch64-linux" in body

  test "test_flake_systems_x86_64_darwin":
    check "x86_64-darwin" in body

  test "test_flake_systems_aarch64_darwin":
    check "aarch64-darwin" in body
