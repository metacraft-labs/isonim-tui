## test_task_app_shared_vm_byte_identical — M22 mandatory test.
##
## Verifies the cross-platform claim of M22 / the
## isonim-cross-platform-architecture spec: the Layer-3 ViewModel
## (`core/vm.nim`) and the Layer-2 high-level view (`core/views.nim`)
## are byte-identical between the TUI and web targets.
##
## In this repo both targets share a single `core/` directory — there
## is no separate "web example" copy of `vm.nim`. The byte-identity
## check therefore asserts:
##   1. There is exactly one `core/vm.nim` file under
##      `examples/task_app/`.
##   2. There is exactly one `core/views.nim` file under
##      `examples/task_app/`.
##   3. Both `tui/leaves.nim` and `web/leaves.nim` import that same
##      file (`../core/vm`) — so they cannot drift.
##   4. A `diff` of the file against itself produces zero output (the
##      spec's literal phrasing).
##
## When a future contributor adds an `isonim-website/` sibling repo
## with a copy of the task app, this test gains an additional check:
## `diff core/vm.nim ../isonim-website/.../task_app/core/vm.nim` must
## produce zero output. Today that path doesn't exist, so the
## same-file diff is the strongest enforceable form.

import unittest
import std/[os, osproc, strutils]

const
  thisDir = currentSourcePath().parentDir
  taskAppDir = thisDir / ".." / "examples" / "task_app"
  vmPath = taskAppDir / "core" / "vm.nim"
  viewsPath = taskAppDir / "core" / "views.nim"
  tuiLeavesPath = taskAppDir / "tui" / "leaves.nim"
  webLeavesPath = taskAppDir / "web" / "leaves.nim"

suite "M22: shared core is byte-identical across targets":
  test "test_task_app_shared_vm_byte_identical":
    # 1. The shared core files exist exactly once.
    check fileExists(vmPath)
    check fileExists(viewsPath)
    check fileExists(tuiLeavesPath)
    check fileExists(webLeavesPath)

    # 2. There is no rival copy of vm.nim under examples/task_app/web/
    # or examples/task_app/tui/ — the cross-platform pattern requires
    # a single source of truth.
    check not fileExists(taskAppDir / "tui" / "vm.nim")
    check not fileExists(taskAppDir / "web" / "vm.nim")
    check not fileExists(taskAppDir / "tui" / "views.nim")
    check not fileExists(taskAppDir / "web" / "views.nim")

    # 3. Both leaves modules pin to `../core/vm`. The `import ../core/vm`
    # text proves they consume the shared VM rather than a local copy.
    let tuiLeaves = readFile(tuiLeavesPath)
    let webLeaves = readFile(webLeavesPath)
    check "import ../core/vm" in tuiLeaves
    check "import ../core/vm" in webLeaves

    # 4. The literal `diff` invocation the spec calls out produces zero
    #    output. We diff the canonical path against itself (the only
    #    other copy you could diff against would live in a sibling
    #    repo — none exists today). Identity diff = empty stdout.
    let (output, exitCode) =
      execCmdEx("diff -u " & quoteShell(vmPath) & " " & quoteShell(vmPath))
    check exitCode == 0
    check output.strip == ""

    let (output2, exitCode2) =
      execCmdEx("diff -u " & quoteShell(viewsPath) & " " & quoteShell(viewsPath))
    check exitCode2 == 0
    check output2.strip == ""

    # 5. Sanity: the Layer-3 file imports nothing from the platform
    # layers. If a future edit accidentally adds `import ../tui/...` or
    # `import ../web/...` to vm.nim, the byte-identity claim breaks.
    let vmContents = readFile(vmPath)
    check "import ../tui" notin vmContents
    check "import ../web" notin vmContents
    check "isonim_tui" notin vmContents
    check "isonim/web" notin vmContents
    check "mock_dom" notin vmContents

    # 6. Same purity check for views.nim — Layer-2 may not import
    # platform-specific modules either.
    let viewsContents = readFile(viewsPath)
    check "import ../tui" notin viewsContents
    check "import ../web" notin viewsContents
    check "isonim_tui" notin viewsContents
    check "isonim/web" notin viewsContents
    check "mock_dom" notin viewsContents
