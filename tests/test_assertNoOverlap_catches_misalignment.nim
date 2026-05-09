## test_assertNoOverlap_catches_misalignment
##
## A deliberately misaligned tree (child wider than parent) makes
## `assertNoOverlap` fail with a list of offending nodes. A
## well-formed tree passes. The assertion result carries enough
## diagnostic info to point at each offending child / parent pair.
##
## We use the harness's `data-test-bounds` injection attribute so the
## misalignment is reproducible regardless of which placeholder
## layout the compositor uses today; the assertion's containment
## check is what we're gating, not the layout's accuracy.

import unittest
import isonim_tui
import std/strutils

suite "M25: assertNoOverlap":
  test "test_assertNoOverlap_catches_misalignment":
    # === Phase 1: well-formed tree passes. ===
    let h1 = newTerminalTestHarness(40, 5)
    h1.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "data-test-bounds", "0,0,40,5")
      let inner = r.createElement("div")
      r.setAttribute(inner, "data-test-bounds", "0,0,20,2")
      r.appendChild(inner, r.createTextNode("hello"))
      r.appendChild(root, inner)
      root)

    let res1 = h1.assertNoOverlap()
    check res1.ok
    check res1.overlaps.len == 0
    h1.dispose()

    # === Phase 2: a misaligned tree fails with a list of offenders.
    # Child claims (0,0,80,1) — 80 cells wide — but parent claims
    # only (0,0,40,1). The assertion catches the horizontal escape.
    let h2 = newTerminalTestHarness(40, 5)
    h2.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "outer")
      r.setAttribute(root, "data-test-bounds", "0,0,40,1")
      let bad = r.createElement("div")
      r.setAttribute(bad, "id", "bad-child")
      # Child width 80 — escapes the 40-cell parent.
      r.setAttribute(bad, "data-test-bounds", "0,0,80,1")
      r.appendChild(bad, r.createTextNode("verywideoverflow"))
      r.appendChild(root, bad)
      root)

    let res2 = h2.assertNoOverlap()
    check (not res2.ok)
    check res2.overlaps.len >= 1
    check res2.message.contains("escapes")

    # The diagnostic message references the child's ids and rectangles.
    let firstOffense = res2.overlaps[0]
    check firstOffense.childWidth == 80
    check firstOffense.parentWidth == 40
    h2.dispose()

    # === Phase 3: a vertical-escape mismatch — child on row 5 but
    # parent ends at row 1.
    let h3 = newTerminalTestHarness(40, 10)
    h3.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "data-test-bounds", "0,0,40,2")
      let bad = r.createElement("div")
      r.setAttribute(bad, "data-test-bounds", "5,0,40,1")
      r.appendChild(bad, r.createTextNode("offrow"))
      r.appendChild(root, bad)
      root)

    let res3 = h3.assertNoOverlap()
    check (not res3.ok)
    check res3.overlaps.len >= 1
    h3.dispose()
