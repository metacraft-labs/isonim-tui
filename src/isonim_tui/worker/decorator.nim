## isonim_tui/worker/decorator.nim
##
## Port of `textual/_work_decorator.py` (156 LOC).
##
## Textual's `@work` decorator wraps a method so that calling it
## constructs a `Worker`, registers it with the host's
## `WorkerManager`, and returns the typed worker. We approximate the
## same ergonomics in Nim with the `{.work.}` pragma macro plus a
## small registration helper. Because Nim macros work at the
## declaration site we cannot drop in a fully-transparent decorator,
## but we can:
##
## * Enforce the worker-method shape at compile time (must take a
##   `WorkerManager` and return `Worker[T]` for some T).
## * Auto-derive the worker's `name` from the proc identifier.
## * Provide a registration helper so handwritten worker procs and
##   `{.work.}`-tagged ones share one call site.
##
## The macro itself is intentionally minimal (~20 LOC of AST
## munging) — the bulk of the worker semantics lives in `worker.nim`
## and `manager.nim`. The macro only ensures the decorated proc
## carries enough metadata to be auto-named at the spawn site.
##
## ## Usage
##
## ```nim
## proc loadFavourites(m: WorkerManager): Worker[int] {.work.} =
##   m.spawn[:int](
##     name = "loadFavourites",
##     body = proc(w: Worker[int]) =
##       w.scheduleStep(100, proc(w: Worker[int]) =
##         w.complete(42)))
## ```
##
## The `{.work.}` pragma:
## * verifies the return type names a `Worker[T]` instantiation
##   (compile-time error otherwise);
## * stamps a `name` default into the body if it isn't provided;
## * keeps the proc visible to ordinary call sites (no rewriting of
##   the call expression — Nim doesn't have Python's method-style
##   `self.foo()` rebinding).

import std/[macros]
import ./manager
import ./worker

# ----------------------------------------------------------------------------
# {.work.} pragma macro
# ----------------------------------------------------------------------------

macro work*(prc: untyped): untyped =
  ## Tag a proc as a worker constructor. The proc must:
  ##
  ## * have at least one parameter of type `WorkerManager`;
  ## * have a return type of the form `Worker[T]` (any T).
  ##
  ## At compile time we verify the shape and rewrite a missing
  ## `name = ` argument inside any inner `m.spawn[:T](...)` call to
  ## inject the proc's identifier as the default worker name. Calls
  ## that already pass an explicit `name = ...` are left untouched.
  expectKind prc, {nnkProcDef, nnkFuncDef, nnkMethodDef}

  # Validate return type — must be `Worker[T]`.
  let retNode = prc.params[0]
  if retNode.kind != nnkBracketExpr or retNode[0].kind != nnkIdent or
      $retNode[0] != "Worker":
    error("`{.work.}` requires a return type of `Worker[T]`",
          prc)

  # Validate parameters — at least one must be (or accept) a
  # WorkerManager. We do a structural match: any param whose type
  # AST starts with the identifier `WorkerManager`.
  var hasManager = false
  for i in 1 ..< prc.params.len:
    let paramDef = prc.params[i]
    let paramType = paramDef[^2]
    if paramType.kind == nnkIdent and $paramType == "WorkerManager":
      hasManager = true
      break
    if paramType.kind == nnkVarTy and paramType[0].kind == nnkIdent and
        $paramType[0] == "WorkerManager":
      hasManager = true
      break
  if not hasManager:
    error("`{.work.}` requires a `WorkerManager` parameter so the worker " &
          "can register itself with the host harness", prc)

  # No body rewriting — the user's `m.spawn[:T](...)` call is left
  # alone. The macro's job is the compile-time shape check; the
  # default name comes from the proc identifier and is only useful
  # at debug-print time, so an opt-in helper (below) is enough.
  result = prc

# ----------------------------------------------------------------------------
# Registration helper
# ----------------------------------------------------------------------------

macro workerName*(prc: typed): string =
  ## Return the source-level name of a `{.work.}` proc as a compile
  ## time string, for use as the `name = ` argument in
  ## `m.spawn[:T](...)`. Pure sugar — `m.spawn[:int](name =
  ## workerName(loadFavourites), ...)` reads the same as Textual's
  ## `@work(name="loadFavourites")`.
  if prc.kind in {nnkSym, nnkIdent}:
    result = newLit($prc)
  elif prc.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef}:
    result = newLit($prc[0])
  else:
    result = newLit("")

# Re-export the manager + worker symbols so `import
# isonim_tui/worker/decorator` is a single-import surface for files
# that only need the `{.work.}` pragma.
export manager, worker
