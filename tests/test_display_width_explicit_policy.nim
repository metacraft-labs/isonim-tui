## test_display_width_explicit_policy
##
## The `func` overloads of `displayWidth` / `clusterDisplayWidth` that take the
## ambiguous-width policy as an ARGUMENT rather than reading
## `text/width.ambiguousWidth`.
##
## ## WHY THESE OVERLOADS EXIST
##
## `displayWidth(r)` and `displayWidth(s)` read a THREADVAR that
## `setAmbiguousWidth` may change at any point in a process's life. That is the
## right default for a terminal application — the policy is a property of the
## terminal the user is sitting at, not of any one call — and it is unusable
## for a caller whose own signature promises `{.noSideEffect.}`, because Nim's
## `func` cannot read mutable global state.
##
## CodeTracer's value-presentation pipeline is the first such caller and its
## requirement is not stylistic: a rendering CLIPPED at a width the process can
## change underneath it is not byte-identical across runs, which is what its
## snapshot testing and its cross-front-end equivalence rest on. So the width
## measure it hands the presenter is `func terminalMeasure(s: string): int`,
## and that only compiles against these overloads.
##
## ## WHAT THIS FILE ASSERTS, AND WHY EACH ARM IS NOT REDUNDANT
##
##   1. THE OVERLOADS ARE CALLABLE FROM A `func`. Asserted by CALLING them from
##      a `func` defined here, so it is a compile-time proof and it is the whole
##      point of the overloads: reintroduce a read of the `ambiguousWidth`
##      threadvar inside one and this file stops compiling with the same error
##      CodeTracer's build hit — `'displayWidth' can have side effects`.
##
##      WHAT IT DOES *NOT* CATCH, measured rather than assumed: changing the
##      `func` keyword back to `proc` does NOT break this file. Nim infers
##      `noSideEffect` for a side-effect-free `proc`, so a `func` may call one.
##      An earlier draft of this comment claimed the keyword was the thing being
##      pinned; it is not, and the distinction matters because the keyword is
##      what a reviewer looks at. What is actually pinned — and what the whole
##      requirement is about — is that the body cannot read mutable global
##      state. That is the stronger property and it is the one enforced.
##   2. THE THREADVAR IS NOT CONSULTED. Every arm below sets the threadvar to
##      the OPPOSITE of the policy it passes. An overload that quietly ignored
##      its argument and read the global would return the other number, and an
##      arm that left the threadvar at its default could not tell the two
##      apart — which is the shape of a test that passes for the wrong reason.
##   3. THE EXPLICIT SPELLING AGREES WITH THE THREADVAR SPELLING when the two
##      hold the same policy. Without this, "pure" could have been bought by
##      changing the answer, and no caller would notice until a snapshot moved.
##   4. GRAPHEME-CLUSTER BEHAVIOUR SURVIVES on the string overload. It is a
##      separate code path (`graphemeClusters` + `clusterDisplayWidth`), and the
##      policy argument had to be threaded through all of it by hand.
##
## No mocks: this is the real `text/width` module and real Unicode data.

import unittest
import std/unicode

import isonim_tui/text/width

const AmbiguousSamples = [
  Rune(0x00A1), ## ¡ INVERTED EXCLAMATION MARK
  Rune(0x00A4), ## ¤ CURRENCY SIGN
  Rune(0x00A7), ## § SECTION SIGN
  Rune(0x00B0), ## ° DEGREE SIGN
  Rune(0x2010), ## ‐ HYPHEN
  Rune(0x2013), ## – EN DASH
  Rune(0x2014), ## — EM DASH
  Rune(0x2018), ## ' LEFT SINGLE QUOTATION MARK
]

const ThreeSections = "\xC2\xA7\xC2\xA7\xC2\xA7" ## three §, EAW=A
const ZwjFamily = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  ## 👨‍👩‍👧 — one grapheme cluster, one wide glyph.

# ---------------------------------------------------------------------------
# ARM 1, and it is a COMPILE-TIME assertion.
#
# These three `func`s exist to be compiled. Nim's `func` is `{.noSideEffect.}`,
# so a `func` that called a threadvar-reading `proc` would not compile — the
# exact error CodeTracer's build hit before these overloads existed:
#
#     Error: 'terminalMeasure' can have side effects
#     > 'terminalMeasure' calls '.sideEffect' 'displayWidth'
#
# Nothing below can be written as a runtime `check`: a compile failure cannot
# be asserted from inside the program that fails to compile.
# ---------------------------------------------------------------------------

func pureRuneWidth(r: Rune; policy: AmbiguousWidth): int =
  displayWidth(r, policy)

func pureStringWidth(s: string; policy: AmbiguousWidth): int =
  displayWidth(s, policy)

func pureClusterWidth(c: string; policy: AmbiguousWidth): int =
  clusterDisplayWidth(c, policy)

func pureMeasure(s: string): int {.gcsafe, raises: [].} =
  ## The exact shape a pure consumer needs: a measure whose only input is its
  ## argument. This is `type_formatters.terminalMeasure` in CodeTracer.
  displayWidth(s, awNarrow)

suite "displayWidth with an explicit ambiguous-width policy":

  setup:
    setAmbiguousWidth(awNarrow) ## restore the library default per test

  teardown:
    setAmbiguousWidth(awNarrow)

  test "test_explicit_policy_overloads_are_callable_from_a_func":
    # The compile-time proof above, exercised so the funcs are not dead code
    # that a future `--opt` pass could drop before the checker looked at it.
    check pureRuneWidth(Rune(0x00A7), awNarrow) == 1
    check pureRuneWidth(Rune(0x00A7), awWide) == 2
    check pureStringWidth(ThreeSections, awNarrow) == 3
    check pureClusterWidth("\u{1F468}", awNarrow) == 2
    check pureMeasure(ThreeSections) == 3

  test "test_rune_overload_ignores_the_threadvar":
    # THE THREADVAR IS SET TO THE OPPOSITE OF THE ARGUMENT in both directions.
    # An overload that read the global instead of its parameter returns the
    # other number here, and an arm that left the global at its default could
    # not tell the two implementations apart.
    setAmbiguousWidth(awWide)
    for r in AmbiguousSamples:
      check displayWidth(r, awNarrow) == 1
      check displayWidth(r) == 2 ## the threadvar spelling still reads it

    setAmbiguousWidth(awNarrow)
    for r in AmbiguousSamples:
      check displayWidth(r, awWide) == 2
      check displayWidth(r) == 1

  test "test_string_overload_ignores_the_threadvar":
    setAmbiguousWidth(awWide)
    check displayWidth(ThreeSections, awNarrow) == 3
    check displayWidth(ThreeSections) == 6

    setAmbiguousWidth(awNarrow)
    check displayWidth(ThreeSections, awWide) == 6
    check displayWidth(ThreeSections) == 3

  test "test_cluster_overload_ignores_the_threadvar":
    setAmbiguousWidth(awWide)
    check clusterDisplayWidth("\xC2\xA7", awNarrow) == 1
    check clusterDisplayWidth("\xC2\xA7") == 2

    setAmbiguousWidth(awNarrow)
    check clusterDisplayWidth("\xC2\xA7", awWide) == 2
    check clusterDisplayWidth("\xC2\xA7") == 1

  test "test_explicit_and_threadvar_spellings_agree_when_the_policy_matches":
    # PURITY MUST NOT HAVE BEEN BOUGHT BY CHANGING THE ANSWER. Without this
    # arm the overloads could return anything at all and every assertion above
    # would still pass.
    for policy in [awNarrow, awWide]:
      setAmbiguousWidth(policy)
      for r in AmbiguousSamples:
        check displayWidth(r, policy) == displayWidth(r)
      check displayWidth(ThreeSections, policy) == displayWidth(ThreeSections)
      check clusterDisplayWidth("\xC2\xA7", policy) ==
        clusterDisplayWidth("\xC2\xA7")

  test "test_non_ambiguous_widths_are_unaffected_by_the_policy":
    # Only EAW=A moves. If the policy argument were being applied to the wrong
    # branch of `eawClass`, ASCII or CJK would move with it.
    for policy in [awNarrow, awWide]:
      check displayWidth(Rune('A'.ord), policy) == 1
      check displayWidth(Rune('z'.ord), policy) == 1
      check displayWidth(Rune(0x6F22), policy) == 2  ## 漢, EAW=W
      check displayWidth(Rune(0xFF65), policy) == 1  ## ･, EAW=H
      check displayWidth(Rune(0x0301), policy) == 0  ## combining acute

  test "test_string_overload_is_still_grapheme_cluster_aware":
    # The policy had to be threaded through `graphemeClusters` +
    # `clusterDisplayWidth` by hand. A ZWJ family counted per CODEPOINT is 6
    # cells; counted per CLUSTER it is 2, which is what a terminal draws.
    for policy in [awNarrow, awWide]:
      check displayWidth(ZwjFamily, policy) == 2
    setAmbiguousWidth(awWide)
    check displayWidth(ZwjFamily, awNarrow) == 2

  test "test_mixed_string_sums_clusters_under_the_given_policy":
    # `A` (1) + `§` (policy) + `漢` (2).
    let s = "A\xC2\xA7\xE6\xBC\xA2"
    setAmbiguousWidth(awWide)
    check displayWidth(s, awNarrow) == 4
    setAmbiguousWidth(awNarrow)
    check displayWidth(s, awWide) == 5
