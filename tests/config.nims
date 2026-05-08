## Tests inherit the repo-root `config.nims`. This file exists so a
## developer running `nim c -r tests/foo.nim` from inside `tests/`
## still sees the same path overrides if Nim only walks the deepest
## config.nims. The compiler actually loads both, so paths here
## *augment* the root settings; we keep this file in sync to be safe
## when an IDE or external tool only loads the closest config.nims.

switch("path", "$config/../src")
switch("path", "$config/../../isonim/src")
switch("path", "$config/../../nim-termctl/src")
switch("path", "$config/../../nim-faststreams")
switch("path", "$config/../../nim-stew")
switch("path", "$config/../../nim-everywhere/src")
