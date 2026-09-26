## Root nim config.nims — applies to every nim invocation in this repo
## (compiler walks up from the source file looking for config.nims).
##
## NOTE on `$projectDir`: it resolves to the directory of the .nim file
## being compiled, NOT to the repo root. Sources live under `src/` and
## `tests/`, so we have to walk up one directory to get back to the
## repo root before stepping sideways into sibling repos.
##
## Mirrors `isonim/tests/config.nims` for sibling-repo discovery.

# Local sources (so `import isonim_tui/...` resolves from src/, tests/, …).
switch("path", "$config/src")

# Sibling isonim — primary dependency.
switch("path", "$config/../isonim/src")

# Sibling isonim-examples — canonical home for shared demo cores
# (EX-M1+). The `examples/task_app/core/{vm,views}.nim` files in this
# repo are re-export shims that pull from `task_app/core/...` which
# resolves via this path.
switch("path", "$config/../isonim-examples")

# Sibling isonim-render-serve — `isonim-examples/task_app/tui/leaves.nim`
# does `import isonim_render_serve/element_tree_attrs`, so anything that
# reaches the shared task-app demo (e.g.
# `tests/test_task_app_tui_snapshot_five_states.nim`) needs this on the
# path. Added in isonim-render-serve@d59bbe5; missing here until CI began
# compiling for real.
switch("path", "$config/../isonim-render-serve/src")

# Sibling nim-termctl — M4 byte-level input parser.
switch("path", "$config/../nim-termctl/src")

# Sibling nim-pty — M9 driver tests open real ptys to drive the
# PosixDriver against simulated terminal I/O.
switch("path", "$config/../nim-pty/src")

# Transitive deps that isonim re-exports.
switch("path", "$config/../nim-faststreams")
switch("path", "$config/../nim-stew")
switch("path", "$config/../nim-everywhere/src")

## Worktree-local nimcache: every Nim compile inside this checkout keeps its
## intermediate files (its nimcache) INSIDE this checkout.
##
## WHY.  Nim's default nimcache is `$XDG_CACHE_HOME/nim/<project>_d` (`_r` for
## -d:release; `%USERPROFILE%\nimcache\<project>_d` on Windows).  It is keyed by
## the project NAME only, and the generated file names inside it do not depend
## on the checkout path either.  So two worktrees or clones of this repository
## that build the same project at the same time write, compile and link each
## other's intermediate files.  Measured on 2026-09-26 in a sibling repository:
## ten concurrent builds of two worktrees that differed in a few places gave
## four correct binaries, two that exited 0 with the OTHER worktree's code
## linked in (one of them a mix of both), two compile failures on
## half-rewritten generated C and two link failures.
##
## WHAT.  `<checkout>/.nimcache/<directory of the main module, relative to the
## checkout>/<module name><suffix>`, where the suffix is Nim's own: `_check`
## for `nim check`, `_r` for -d:release or -d:danger, `_d` otherwise.  The
## directory is part of the key, so same-named modules in different directories
## no longer share a cache either.  Only the intermediates move; build outputs
## stay where they were.  An explicit `--nimcache:` on the command line still
## wins, because Nim applies the command line again after the config files.
## `nim js` and project-less invocations are left alone.
##
## HOW IT IS PICKED UP.  Nim runs the `config.nims` of every PARENT directory of
## the compiled module, outermost first, then the one in the module's own
## directory.  So this file applies to every compile under this checkout,
## `just`, `nimble`, CI and a bare `nim c` alike, whatever the working directory.
## `--skipParentCfg` switches it off for modules below the checkout root, so a
## recipe that passes that flag must name its own checkout-local `--nimcache:`.
## Nothing in this repository passes `--skipParentCfg` today.
## `tests/test_nimcache_is_worktree_local.nim` checks the layout, and fails if the
## config is bypassed; its `--skipParentCfg` negative control proves the probe
## can see a shared cache at all.
##
## WINDOWS.  Nim turns the `/` below into `\` on a Windows host.  The layout adds
## `\.nimcache\<module dir>\<module>_d\` in front of Nim's own object file names,
## so keep the checkout root short (about 80 characters) to stay inside MAX_PATH.
block worktreeLocalNimcache:
  var project = projectName()
  if project.len > 4 and project[^4 .. ^1] == ".nim":
    project = project[0 ..< ^4]
  # No project (`nim dump` with no file): nothing to place.  The JS backend
  # has its own convention (a cache next to its output).  `nim e` never
  # generates C, so it never creates the directory.
  if project.len == 0 or getCommand() == "js":
    break worktreeLocalNimcache

  # Plain "/" joins, NOT std/os `/`: NimScript's `/` follows the TARGET OS,
  # so a `--os:windows` cross-compile on a POSIX host would get backslashes.
  let root = thisDir()
  let projDir = projectDir()
  var rel = ""
  if projDir.len >= root.len and projDir[0 ..< root.len] == root:
    rel = projDir[root.len .. ^1]
  else:
    # Cannot happen for a project Nim found this file for (this file is read
    # because it sits in a parent of the project directory).  Stay inside
    # the checkout and stay unique anyway.
    rel = "_outside/"
    for c in projDir:
      rel.add(if c in {'/', '\\', ':'}: '_' else: c)
  while rel.len > 0 and rel[0] in {'/', '\\'}:
    rel = rel[1 .. ^1]

  let suffix =
    if getCommand() == "check": "_check"
    elif defined(release) or defined(danger): "_r"
    else: "_d"
  var cacheDir = root & "/.nimcache"
  if rel.len > 0:
    cacheDir.add("/" & rel)
  switch("nimcache", cacheDir & "/" & project & suffix)
