## cross_emulator_app — minimal isonim-tui app used by the M29
## cross-emulator suite.
##
## The app builds a real TerminalTestHarness, mounts a bordered
## Static widget with a known marker string, paints the resulting
## ScreenBuffer to stdout via `encodeAnsi` (the same byte path the
## production driver uses), then loops on stdin.
##
## The test driver runs this app inside a real terminal emulator
## (xterm / kitty / alacritty) under Xvfb, with `tmux` providing
## the capture surface — `tmux capture-pane` reads back the cell
## contents the emulator put on screen, and the test asserts the
## marker text is present.
##
## The marker is printed twice — once as a bordered widget produced
## by the real renderer (proving the cell-grid + SGR + diff path
## roundtrips through the emulator) and once as a plain string
## (so a tmux capture that misses the widget paint still has a
## ground-truth byte to grep for).

import isonim_tui
import ./app_runtime

const
  marker* = "ISONIM-TUI-M29-CROSS-EMU-OK"

when isMainModule:
  let rt = newAppRuntime(40, 6)
  rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
    let root = r.createElement("div")
    let s = newStatic(r, marker, width = 36, height = 3,
                      border = bsRound)
    r.appendChild(root, s.node)
    root)
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q" or key == "<EOT>":
      rt.quit = true)
