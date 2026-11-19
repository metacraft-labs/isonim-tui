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
          # kitty and alacritty draw with OpenGL, and under Xvfb that GL is
          # provided through Xvfb's GLX extension, which loads mesa's DRI
          # driver. A Nix-built Xvfb finds that driver through
          # /run/opengl-driver, which exists only on NixOS, so on the CI
          # runners (and any non-NixOS host) Xvfb came up without GLX: kitty
          # failed with "GLX: GLX extension not found ... kitty requires
          # working OpenGL 3.1 drivers", alacritty with "failed to create
          # EGLDisplay", and the M29 cross-emulator test saw no session.
          # xvfb-run is wrapped to hand Xvfb mesa's software (llvmpipe)
          # drivers; nothing else in the shell sees these variables.
          withMesaGl =
            drv: exe:
            pkgs.symlinkJoin {
              name = "${drv.name}-mesa-gl";
              paths = [ drv ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postBuild = ''
                wrapProgram $out/bin/${exe} \
                  --set LIBGL_DRIVERS_PATH ${pkgs.mesa}/lib/dri \
                  --set __EGL_VENDOR_LIBRARY_FILENAMES ${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
                  --set __GLX_VENDOR_LIBRARY_NAME mesa \
                  --set GBM_BACKENDS_PATH ${pkgs.mesa}/lib/gbm \
                  --prefix LD_LIBRARY_PATH : ${pkgs.mesa}/lib
              '';
            };
          # The committed `.pre-commit-config.yaml` is what the pre-commit hook
          # runs, with the flake's pre-commit: the flake provides the tools, the
          # committed config provides the rules. git-hooks.nix's own installer
          # refuses to replace a committed config and then installs nothing.
          installGitHooks = ''
            bash ${./scripts/install-git-hooks.sh} ${pkgs.lib.getExe preCommit.config.package} || exit $?
          '';
          # The hooks are installed into
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
            # A clone where git-hooks.nix's own installer once ran keeps its RELATIVE
            # core.hooksPath `.git/hooks`, in the config every worktree shares. A linked
            # worktree cannot resolve it (there `.git` is a file), so git silently runs
            # no hooks there. Point it at the common hooks directory instead.
            if [ "$(${pkgs.git}/bin/git config --local --get core.hooksPath 2>/dev/null)" = .git/hooks ]; then
              ${pkgs.git}/bin/git config --local core.hooksPath "$(${pkgs.git}/bin/git rev-parse --path-format=absolute --git-common-dir)/hooks"
            fi
            # `pre-commit install` (and git-hooks.nix's installer, where it once ran)
            # moves each Reprobuild hook dispatcher aside to `<hook>.legacy` and puts
            # its shim in the slot, so the managed hook (for pre-push, the publication
            # gate) runs only by accident. Put the dispatcher back and chain the shim as
            # `<hook>.repro-local`, which the dispatcher runs: the layout
            # `repro hooks ensure --vcs` produces.
            _hooks="$(${pkgs.git}/bin/git rev-parse --path-format=absolute --git-path hooks 2>/dev/null || true)"
            for _legacy in "$_hooks"/*.legacy; do
              [ -f "$_legacy" ] && grep -q 'reprobuild hook dispatcher' "$_legacy" || continue
              _slot="''${_legacy%.legacy}"
              if [ -f "$_slot" ] && grep -q 'reprobuild hook dispatcher' "$_slot"; then
                rm -f "$_legacy"
              elif [ ! -e "$_slot" ] || grep -Eq '^# File generated by (pre-commit|prek)' "$_slot"; then
                if [ -f "$_slot.repro-local" ] && ! grep -Eq '^# File generated by (pre-commit|prek)' "$_slot.repro-local"; then
                  echo "git-hooks: $_slot.repro-local is your own hook; run 'repro hooks ensure --vcs' to reconcile." >&2
                  continue
                fi
                if [ -e "$_slot" ]; then mv -f "$_slot" "$_slot.repro-local"; fi
                mv -f "$_legacy" "$_slot"
              else
                echo "git-hooks: $_slot is not a pre-commit shim; run 'repro hooks ensure --vcs' to reconcile." >&2
              fi
            done
            unset _hooks _legacy _slot
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
            packages =
              with pkgs;
              [
                nim
                nimble
                just
                nixfmt-rfc-style
                # Sanitizer-augmented Nim builds need clang on Linux.
                clang
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
                # a shared tmux socket). kitty and alacritty need OpenGL,
                # which Xvfb provides once it has mesa (`withMesaGl`).
                xterm
                tmux
                kitty
                alacritty
              ]
              # Linux leak checking and the existing Xvfb-backed M29 emulator lane.
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
                pkgs.valgrind
                (withMesaGl pkgs.xvfb-run "xvfb-run")
              ];
            shellHook = ''
              ${ownRepoOnly installGitHooks}
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
