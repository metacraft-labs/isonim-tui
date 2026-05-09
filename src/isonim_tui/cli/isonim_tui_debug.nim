## isonim-tui-debug — CLI stub for the live layout-debug overlay.
##
## *Stub status* (M25 deferred): the live mode that runs an arbitrary
## TUI app and writes annotated SVGs every N frames to a watch file
## (so an external SVG viewer can hot-reload) lands in a follow-up
## milestone. Today this CLI demonstrates the underlying primitives
## by reading a pre-recorded session and writing annotated SVGs for
## each frame to a directory the user passes.
##
## Run: `isonim-tui-debug --replay <recording.json> --out <dir>` —
##      writes one `<dir>/frame-000.svg`, `<dir>/frame-001.svg`, …
##      with the default overlay set (boxes / focus / dirty).

import std/[os, strutils]

import ../testing/recorder
import ../testing/recording_types
import ../testing/snapshot/svg as svgMod

const usage = """isonim-tui-debug — annotated SVG dumper.

Usage:
  isonim-tui-debug --replay <recording.json> --out <directory>
  isonim-tui-debug --help

Stub: the live mode that writes overlays every N frames in real time
ships in a later milestone. Today this CLI dumps per-frame SVGs from
a pre-recorded session — useful for visual inspection of replay-
diff'd content.
"""

proc cmdReplay(recordingPath, outDir: string): int =
  if not fileExists(recordingPath):
    stderr.writeLine "isonim-tui-debug: recording not found: " & recordingPath
    return 2
  let recording = Recording.load(recordingPath)
  createDir(outDir)
  for i, frame in recording.frames:
    let svg = svgMod.encodeSvg(frame.buffer)
    let path = outDir / ("frame-" & align($i, 3, '0') & ".svg")
    writeFile(path, svg)
  echo "wrote ", recording.frames.len, " SVG frame(s) to ", outDir
  return 0

proc main(): int =
  let args = commandLineParams()
  if args.len == 0 or args[0] in @["-h", "--help"]:
    echo usage
    return 0
  var recordingPath = ""
  var outDir = ""
  var i = 0
  while i < args.len:
    case args[i]
    of "--replay":
      if i + 1 >= args.len:
        stderr.writeLine "isonim-tui-debug: --replay requires a path"
        return 1
      recordingPath = args[i + 1]
      i += 2
    of "--out":
      if i + 1 >= args.len:
        stderr.writeLine "isonim-tui-debug: --out requires a directory"
        return 1
      outDir = args[i + 1]
      i += 2
    else:
      stderr.writeLine "isonim-tui-debug: unknown arg: " & args[i]
      return 1
  if recordingPath.len == 0 or outDir.len == 0:
    stderr.writeLine usage
    return 1
  return cmdReplay(recordingPath, outDir)

when isMainModule:
  quit(main())
