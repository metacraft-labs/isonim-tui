## isonim-tui-record — CLI stub for recording bug-report sessions.
##
## *Stub status* (M25 deferred): the interactive front-end that
## attaches to a running TUI app, tees inputs into a `Recording`, and
## dumps it on exit lands in a follow-up milestone (see `M27` for the
## production-release pass). The pieces it needs — a real-pty driver
## that surfaces inputs, the recorder, and the JSON serialiser — are
## already in place; what's missing is the supervised process model
## that runs another binary.
##
## What this CLI *does* today: load a recording from disk and print a
## one-line summary so users / CI can sanity-check JSON files
## produced programmatically. The same JSON format is the wire
## format `RecordingHarness` writes, so this is enough to verify the
## round-trip surface from the command line.
##
## Run: `isonim-tui-record --info <path>` — prints frame / event
##      count and dimensions.
##      `isonim-tui-record --version` — prints the recording wire
##      version we understand.

import std/[os, strutils]

import ../testing/recorder
import ../testing/recording_types

const usage = """isonim-tui-record — recording inspector / loader.

Usage:
  isonim-tui-record --info <path>
  isonim-tui-record --version
  isonim-tui-record --help

Stub: the interactive recorder that attaches to a running TUI app
ships in a later milestone. Today this CLI only inspects pre-recorded
sessions written by `RecordingHarness` (the in-process API).
"""

proc cmdInfo(path: string): int =
  if not fileExists(path):
    stderr.writeLine "isonim-tui-record: file not found: " & path
    return 2
  try:
    let r = Recording.load(path)
    echo "version=", r.version
    echo "dimensions=", r.cols, "x", r.rows
    echo "events=", r.events.len
    echo "frames=", r.frames.len
    return 0
  except CatchableError as e:
    stderr.writeLine "isonim-tui-record: failed to parse: " & e.msg
    return 3

proc main(): int =
  let args = commandLineParams()
  if args.len == 0 or args[0] in @["-h", "--help"]:
    echo usage
    return 0
  case args[0]
  of "--version", "-v":
    echo "isonim-tui-record (recording wire version ", recordingVersion, ")"
    return 0
  of "--info", "-i":
    if args.len < 2:
      stderr.writeLine "isonim-tui-record: --info requires a path"
      return 1
    return cmdInfo(args[1])
  else:
    if not args[0].startsWith("-") and fileExists(args[0]):
      return cmdInfo(args[0])
    stderr.writeLine "isonim-tui-record: unknown argument: " & args[0]
    stderr.writeLine usage
    return 1

when isMainModule:
  quit(main())
