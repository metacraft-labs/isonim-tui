# Native hot module reload

IsoNim's TUI target can hot-reload a running application: you edit a `.nim`
file, Reprobuild recompiles it, the Reprobuild HCR agent swaps the code inside
the live process, and the reconciler updates the affected widget without
re-mounting the tree or losing component state.

This page is about the **native** path. The browser target's HMR is a different
mechanism with the same user-visible behaviour; see
`isonim-specs/Hot-Module-Reload.md`.

Design: `isonim-specs/Hot-Module-Reload-Native.md`.
Milestones: `Hot-Module-Reload-Native.milestones.org` (NH-M0 … NH-M5).
The transport's normative ordering: `reprobuild-specs/HCR/Patch-Loading-Lifecycle.md`.

## The two flags

| Flag | What it turns on |
|---|---|
| `-d:isonimHmr` | the IsoNim runtime: `HmrRoot`, the ui-slot registry, `mountUiHot`, `hmrSignal`, and the two agent callbacks |
| `-d:reprobuildHcr` | the FFI bindings in `isonim/native/hcr.nim`, so the ten `rb_hcr_*` calls resolve into `librepro_hcr_agent` instead of no-op fallbacks |

They are orthogonal. With neither, the binary is the one you ship: `mountUiHot`
is a build-once mount, `hmrSignal` is `createSignal`, and no `rb_hcr_*` symbol
appears in the image at all.

## Writing an app that can reload

```nim
import isonim/native/hmr
import isonim_tui/renderer
import isonim_tui/reconciler
import isonim/native/reconciler

proc entry() =
  # One registration per ui block. The hash is what decides whether a block
  # changed, so it must be recomputed by the patched code — see below.
  hmrRegisterFactory(SlotHeader, headerHash(), makeHeader())

let root = newHmrRoot(entry)
root.start()                      # installs rb_hcr_before_reload / _after_reload

let mount = mountUiHot(proc(): TerminalNode = buildRoot(),
                       NativeRootMount[TerminalNode](sink))

# once per frame
discard root.pumpReload()         # HCR-Overview §13.6's synchronized poll
```

Two rules the framework cannot enforce for you:

* **Everything reactive must live inside a ui slot.** A factory that reads a
  view-model signal *outside* any slot re-subscribes the mount seam to that
  signal, and an unrelated view-model write then rebuilds the whole root.
* **Keep `pumpReload` on the thread that owns the tree.** The agent's
  synchronized mode (`repro_hcr_agent_set_synchronized_mode(1)`) parks the patch
  until you call it, which is what keeps both reload callbacks — and therefore
  every tree mutation — on your frame loop rather than on the agent's detached
  thread.

## What happens on a reload, and in what order

```
Phase E  rb_hcr_before_reload   OLD code is the only code in the process.
                                IsoNim flips the generation, opens the staging
                                window, and runs your `onBeforeReload` hook —
                                the one place to save state whose layout is
                                about to change.
Phase F  the patch is loaded
Phase G  trampolines installed  NEW code becomes live HERE, and only here.
Phase H  rb_hcr_after_reload    IsoNim re-runs `entry()`. The patched bodies
                                register their new hashes; every hash that
                                moved writes its slot's factory signal, which
                                invalidates that slot's memo, which re-emits
                                the tree. Slots whose hash did not move are
                                served from the memo and are not rebuilt.
```

The order is normative and is not negotiable: at Phase E no patch has been
loaded, so a registration pass run there would re-register the *old* hashes and
the reload would be a silent no-op.

If the entry call raises, IsoNim rolls the generation back, discards the staged
registrations and leaves the painted surface exactly as it was. If the *load*
fails after Phase E — `Patch-Loading-Lifecycle.md` §3.3 step 38 — the agent
still calls `after_reload` with zero `changed_types`; IsoNim needs no branch for
that case, because the entry simply re-registers the hashes it already has.

## Running the real cycle on Linux

`just test-real-agent-hmr` is the end-to-end gate
(`tests/test_real_agent_tui_hmr_cycle.nim`). It is **opt-in** and not part of
`just test`, because it is the one recipe that reaches outside this checkout: it
needs a sibling `../reprobuild`, from which it builds
`librepro_hcr_agent.so` and the `hcr_patch_driver` coordinator. It does not
skip when that is missing — it fails with the remedy.

The same three pieces are what you need to hot-reload your own app by hand:

1. **Build the agent library** and link against it.

   ```sh
   ../reprobuild/libs/repro_hcr_agent/build_lib.sh /tmp/agent
   nim c -d:isonimHmr -d:reprobuildHcr \
       --passC:-I../reprobuild/libs/repro_hcr_agent/c \
       --passC:-fpatchable-function-entry=16,0 \
       --passC:-falign-functions=16 \
       --passC:-fcf-protection=full \
       --passC:-ftls-model=global-dynamic \
       --passL:-L/tmp/agent --passL:-Wl,-rpath,/tmp/agent \
       --passL:-Wl,--build-id=sha1 \
       myapp.nim
   ```

   The `-fpatchable-function-entry` sled is not optional: a function compiled
   without it is refused with `absent-sled` rather than patched.

2. **Start the coordinator first, then the app.** The in-process agent dials
   out once at start-up, with a bounded retry and no later attempt, so a
   coordinator that is not yet listening means the app can never be patched.

   ```sh
   nim c -o:/tmp/hcrdrv ../reprobuild/scripts/hcr_patch_driver.nim
   /tmp/hcrdrv --socket /tmp/hcr.sock --target-symbol my_hot_function \
       --session --session-dir /tmp/hcr-session &
   REPRO_HCR_AGENT_SOCKET=/tmp/hcr.sock ./myapp
   ```

   Keep the socket path short — `sockaddr_un.sun_path` is 108 bytes, and the
   failure when you exceed it is a bare "socket path too long".

3. **Publish an edit.** Recompile the changed module alone and drop a request
   into the session directory:

   ```sh
   nim c --noLinking:on --nimcache:/tmp/nc --stackTrace:off --lineTrace:off \
       --checks:off --opt:speed myhotmodule.nim
   printf '{"patchObject":"%s","patchSymbol":"my_hot_function","patchId":"e1"}' \
       "$(grep -l . /tmp/nc/*.o | head -1)" > /tmp/hcr-session/req-1.json.tmp
   mv /tmp/hcr-session/req-1.json.tmp /tmp/hcr-session/req-1.json
   ```

   Session mode serves many patches on one connection, so the second and
   later edits of a session work the same way.

## The constraint that shapes what you can patch today

The Linux provider uses **Direct Patch Injection**: the replacement body is
copied into a provider-owned page verbatim, and **no relocations are applied to
it**. A patched function that calls anything emits `R_X86_64_PLT32` relocations
and is refused.

In practice that means the hot-swappable unit today is a **leaf** — a function
that computes from its arguments and returns, calling nothing. The pattern the
gate uses is to make the leaf return a small value that the ui block reads and
folds into its slot hash, which is enough to drive the whole
entry -> hash -> signal -> memo -> reconciler -> repaint chain. Patching the
`{.uiComponent.}`-generated registration proc itself needs either a relocating
direct-injection path or the Shared Library mode of
`Patch-Loading-Lifecycle.md` §3.1; neither is available on Linux yet.

`hcr_patch_driver` refuses a relocation-carrying body by default and tells you
which relocations it found, so you learn this from the coordinator rather than
from a jump into garbage.
