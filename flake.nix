{
  description = "isonim-tui - production terminal renderer for IsoNim (cell primitives, RendererBackend conformance, future TUI runtime)";

  inputs = {
    nixos-modules.url = "github:metacraft-labs/nixos-modules";
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
              pkg-config
            ];
            shellHook = ''
              ${preCommit.shellHook}
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
