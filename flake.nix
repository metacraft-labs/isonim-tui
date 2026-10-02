{
  description = "isonim-tui - production terminal renderer for IsoNim (cell primitives, RendererBackend conformance, future TUI runtime)";

  inputs = {
    nixos-modules.url = "github:metacraft-labs/devops-modules";
    nixpkgs.follows = "nixos-modules/nixpkgs-unstable";
    flake-parts.follows = "nixos-modules/flake-parts";
    git-hooks.follows = "nixos-modules/git-hooks-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem =
        { pkgs, system, ... }:
        let
          # git-hooks.nix installs `.pre-commit-config.yaml` and git hooks into
          # `git rev-parse --show-toplevel` of the directory the shell is entered
          # from, so `nix develop /path/to/<this repo>` run inside another checkout
          # would plant this repository's hooks there. `ownRepoOnly` runs a snippet
          # only when that toplevel is this repository, recognised by a `flake.nix`
          # identical to the one this shell was evaluated from; anything it cannot
          # establish counts as another repository, so it fails safe.
          # tests/test_dev_shell_writes_nothing_elsewhere.sh
          ownRepoOnly = script: ''
            _own_repo_root="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
            if [ -n "$_own_repo_root" ] && [ -f "$_own_repo_root/flake.nix" ] \
              && [ "$(${pkgs.coreutils}/bin/sha256sum "$_own_repo_root/flake.nix" | ${pkgs.coreutils}/bin/cut -d' ' -f1)" \
                = "${builtins.hashFile "sha256" ./flake.nix}" ]; then
            ${script}
            # git-hooks.nix's installer leaves core.hooksPath as the RELATIVE
            # `.git/hooks`, in the config every worktree shares. A linked worktree
            # cannot resolve it (there `.git` is a file), so git silently runs no
            # hooks there. Point it at the common hooks directory instead.
            if [ "$(${pkgs.git}/bin/git config --local --get core.hooksPath 2>/dev/null)" = .git/hooks ]; then
              ${pkgs.git}/bin/git config --local core.hooksPath "$(${pkgs.git}/bin/git rev-parse --path-format=absolute --git-common-dir)/hooks"
            fi
            fi
            unset _own_repo_root
          '';
          preCommit = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              check-added-large-files = {
                enable = true;
                args = [ "--maxkb=1200" ];
              };
              check-merge-conflicts.enable = true;
              lint = {
                enable = true;
                name = "just lint";
                entry = "just lint";
                language = "system";
                pass_filenames = false;
              };
            };
          };
        in
        {
          checks.pre-commit = preCommit;
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nim
              nimble
              just
              nixfmt-rfc-style
              # Sanitizer-augmented Nim builds need clang on Linux.
              clang
              # Valgrind for the secondary leak-budget check.
              valgrind
              # Markdown / shell linting.
              markdownlint-cli2
              shellcheck
              shfmt
              # M19: tree-sitter runtime for the TextArea syntax
              # highlighter. Vendored grammars (parser.c + scanner.c)
              # are compiled in via {.compile.}; the runtime library
              # itself is linked from this dev-shell package.
              tree-sitter
              # `tree-sitter generate` (the `grammars` Justfile recipe) loads
              # the grammar's `grammar.js` through node; without it the CLI
              # fails with "Failed to run `node`". codetracer's nix package
              # runs the same generate step with nodejs on PATH.
              nodejs
              pkg-config
              # M29 cross-emulator suite. xvfb-run hosts a virtual X
              # display so xterm can run headless; tmux acts as the
              # in-emulator capture surface (each emulator launches
              # `tmux new-session` and the test reads back the pane via
              # a shared tmux socket). kitty + alacritty are listed for
              # completeness but require GPU/Wayland paths that aren't
              # reliable under Xvfb in CI — the test driver detects
              # missing emulators and reports them as deferred rather
              # than failing.
              xvfb-run
              xterm
              tmux
              kitty
              alacritty
            ];
            shellHook = ''
              ${ownRepoOnly preCommit.shellHook}
              echo "isonim-tui dev shell - nim $(nim --version 2>&1 | head -1)"
            '';
          };
          packages.default = pkgs.stdenvNoCC.mkDerivation {
            pname = "isonim-tui";
            version = "0.1.0";
            src = ./.;
            installPhase = ''
              mkdir -p $out
              cp -R src isonim_tui.nimble README.md LICENSE $out/
            '';
          };
        };
    };
}
