## NH-M4 — the ONE source file the "developer edit" rewrites.
##
## `tests/test_real_agent_tui_hmr_cycle.nim` copies this file, changes the
## integer literal below, recompiles the COPY with `nim c --noLinking`, and
## hands the resulting function body to the real Reprobuild HCR agent over the
## real agent socket. So the patch that reaches the running TUI application is
## the output of a real Nim recompile of a real source edit, not a
## hand-assembled literal and not a C stand-in.
##
## WHY THE MODULE IS THIS SMALL, and why the proc looks the way it does. The
## Linux provider's Direct Patch Injection path (`Patch-Loading-Lifecycle.md`
## §3.2) copies the replacement body into a provider-owned page verbatim: it
## applies no relocations to it, and `hcr_patch_driver` refuses a body that
## carries any. A Nim proc that calls anything — including the framework's own
## `hmrRegisterFactory` — emits `R_X86_64_PLT32` relocations and cannot be
## delivered that way. So the patched function is a LEAF returning a small
## integer, and the ui block reads it. Measured on this host, the compiled body
## is `endbr64; mov eax,<n>; ret` — ten bytes, zero relocations.
##
## The consequence for what the gate proves is stated rather than hidden: the
## `{.uiComponent.}` `symBodyHash` is not what changes here. The entry pass
## derives the slot hash from this proc's RETURN VALUE, so the chain
## "Phase H re-runs the entry -> the entry observes post-swap code -> the slot
## hash moves -> the factory signal is written -> the memo is invalidated ->
## the reconciler mutates the live terminal tree -> the ScreenBuffer repaints"
## is exercised end to end against the real agent, with only the first link
## (source text -> hash) standing in for the macro's compile-time hash. Making
## the macro-generated registration proc itself patchable needs a relocating
## Direct Patch Injection path or the Shared Library mode of §3.1, neither of
## which the Linux provider offers today; that is recorded under NH-M4's
## residue rather than papered over.
##
## `{.exportc.}` gives the proc a real, stable ELF symbol name the agent can be
## handed; `{.noinline.}` keeps it a function with its own body and its own
## `__patchable_function_entries` sled entry in the target build. The literal
## on the last line is the whole editable surface — the harness rewrites the
## digits and nothing else, and asserts the rewrite changed exactly one line.

const Nhm4HeaderSymbol* = "isonim_nhm4_header_version"
  ## The ELF symbol name, in one place, so the fixture, the target's symbol
  ## table hand-off and the harness's `--target-symbol` cannot drift apart.

proc nhm4HeaderVersion*(): cint
    {.exportc: "isonim_nhm4_header_version", noinline.} =
  1
