## test_widget_set_snapshot_windows — M10 mandatory test (deferred to M11).
##
## *Status:* deferred.
##
## The Tier-1 widget set (Static / Label / Container / Placeholder /
## Rule) lands in M11. This test will compare the M11 reference
## snapshot against what `WindowsDriver` paints into a real Windows
## console — verifying that border-style fallback to ASCII on legacy
## `cmd.exe` is the only documented divergence from the POSIX
## snapshot.
##
## On every host (Windows or otherwise) we currently emit `skip()`
## with an informational message; once M11 is in place this test will
## actually assert.

import std/[unittest]

suite "M10: Tier-1 reference snapshot on Windows":

  test "test_widget_set_snapshot_windows":
    skip()
    # M11 has not landed yet — Tier-1 widgets (Static / Label /
    # Container / Placeholder / Rule) are required to render the
    # reference scene this test diffs against. The full implementation
    # will:
    #
    #   1. Build the Tier-1 reference scene via the M11 widget API.
    #   2. Drive it through `WindowsDriver` against a real console.
    #   3. Capture the output through the standard six-format snapshot
    #      runner (`snapPlain`, `snapAnsi`, `snapCellmap`, `snapSvg`,
    #      `snapAnnotatedSvg`, `snapTreedump`).
    #   4. Compare against the canonical fixture stored under
    #      `tests/snapshots/widget_set_reference_windows/`.
    #
    # The legacy `cmd.exe` ASCII-border-style fallback is the only
    # documented divergence; that fork lives in a separate
    # `test_widget_set_snapshot_windows_legacy_cmd.nim`.
