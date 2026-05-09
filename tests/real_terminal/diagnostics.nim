## diagnostics.nim — failure-diagnostic bundle writer for M29.
##
## When a real-terminal test fails, call `writeFailureBundle(...)` to
## persist the full pty byte transcript, the libvterm-rendered final
## screen as plain text + SVG, and a placeholder for the equivalent
## M2-headless snapshot. The bundle lands under
## `test-logs/real-terminal/<test-name>/`.

import std/[os, strutils]

import term_assert

import ./test_helpers

proc renderFinalScreen(s: var TuiTestSession): string =
  ## Capture the libvterm-rendered final screen as plain text using the
  ## same encoder isonim-tui uses for goldens.
  s.screenContents()

proc renderFinalSvg(s: var TuiTestSession): string =
  ## Minimal SVG rendering of the final screen — a vertical column of
  ## text lines. We don't reuse isonim-tui's snapshot SVG encoder
  ## because the harness's libvterm Screen isn't a `ScreenBuffer`. The
  ## intent is human-readable visualisation, not pixel-exact replay.
  let body = s.screenContents()
  let lines = body.splitLines()
  var svg = "<svg xmlns='http://www.w3.org/2000/svg' " &
            "width='800' height='" & $(lines.len * 16 + 20) & "'>" &
            "<rect width='100%' height='100%' fill='#000'/>"
  for i, line in lines:
    let escaped = line.multiReplace([("&", "&amp;"), ("<", "&lt;"),
                                     (">", "&gt;")])
    svg.add "<text x='4' y='" & $((i + 1) * 16) & "' " &
            "fill='#cfd' font-family='monospace' font-size='14'>" &
            escaped & "</text>"
  svg.add "</svg>"
  svg

proc writeFailureBundle*(s: var TuiTestSession; testName: string;
                        message: string) =
  ## Write a diagnostics bundle for `testName`. Safe to call from a
  ## test's `except` block. The harness session must still be alive
  ## (callable) when this runs.
  let dir = bundleDir(testName)
  writeFile(dir / "message.txt", message)
  writeFile(dir / "final.txt", renderFinalScreen(s))
  writeFile(dir / "final.svg", renderFinalSvg(s))
  # The pty transcript: TermAssert doesn't expose raw bytes
  # historically; libvterm consumed them. We instead persist the final
  # parsed screen — the in-process snapshot from a paired M2 test is
  # the divergence-detection reference, but it has to be wired by the
  # caller (it lives in tests/snapshots/ and is supplied as the third
  # argument when applicable).
  writeFile(dir / "README.txt",
    "M29 real-terminal failure bundle.\n" &
    "  message.txt   - the assertion or exception message\n" &
    "  final.txt     - libvterm's final parsed screen as plain text\n" &
    "  final.svg     - same content as a one-pixel-per-cell SVG\n" &
    "Compare against the equivalent in-process snapshot under\n" &
    "tests/snapshots/<widget>/ to localise the divergence between the\n" &
    "headless (M2) and real-pty (M29) tiers.\n")

proc bundleHeadlessSnapshot*(testName: string; snapshotName: string) =
  ## Copy the matching in-process M2 snapshot directory into the
  ## bundle, if it exists. Tests call this from their `except` block
  ## after `writeFailureBundle` to wire up the cross-tier comparison.
  let dir = bundleDir(testName)
  let here = currentSourcePath().parentDir()
  let snapDir = here.parentDir() / "snapshots" / snapshotName
  if not dirExists(snapDir): return
  let dst = dir / "headless_snapshot"
  createDir(dst)
  for kind, path in walkDir(snapDir):
    if kind == pcFile:
      copyFile(path, dst / extractFilename(path))
