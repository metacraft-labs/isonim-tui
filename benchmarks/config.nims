## benchmarks/config.nims — augment the root config so a developer
## running `nim c -r benchmarks/foo.nim` from inside `benchmarks/`
## still picks up sibling-repo paths even if the IDE only loads the
## deepest config.nims. The compiler does load the root config too;
## we keep this in sync as a belt-and-braces measure.

switch("path", "$config/../src")
switch("path", "$config/../../isonim/src")
switch("path", "$config/../../nim-termctl/src")
switch("path", "$config/../../nim-pty/src")
switch("path", "$config/../../nim-faststreams")
switch("path", "$config/../../nim-stew")
switch("path", "$config/../../nim-everywhere/src")
switch("path", "$config/standard_app")
