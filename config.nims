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

# Sibling nim-termctl — M4 byte-level input parser.
switch("path", "$config/../nim-termctl/src")

# Sibling nim-pty — M9 driver tests open real ptys to drive the
# PosixDriver against simulated terminal I/O.
switch("path", "$config/../nim-pty/src")

# Transitive deps that isonim re-exports.
switch("path", "$config/../nim-faststreams")
switch("path", "$config/../nim-stew")
switch("path", "$config/../nim-everywhere/src")
