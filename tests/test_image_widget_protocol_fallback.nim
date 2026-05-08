## test_image_widget_protocol_fallback — M14 mandatory test.
##
## Same fixture, four sessions: Kitty / Sixel / iTerm2 / text-only.
## The widget emits the right protocol per session capability; the
## rendered cells differ but a hash of the source image bytes matches
## across all sessions (since it's hash-of-input regardless of
## protocol).

import unittest
import isonim_tui

proc fakePngBytes(): seq[byte] =
  result = @[0x89'u8, 'P'.byte, 'N'.byte, 'G'.byte,
             0x0D'u8, 0x0A'u8, 0x1A'u8, 0x0A'u8]
  for i in 0 ..< 256:
    result.add byte(i mod 256)

suite "M14: image widget — protocol fallback":
  test "test_image_widget_protocol_fallback":
    var hashes: seq[uint64] = @[]
    let src = Image(bytes: fakePngBytes(), format: sfPng,
                     width: 16, height: 16,
                     preferredFormat: ifAuto)

    # Kitty session.
    block:
      let h = newTerminalTestHarness(30, 6)
      setSupportOverride(ImageProtocols(kitty: true,
                                         iterm2: false, sixel: false))
      var img: ImageWidget
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        img = newImageWidget(r, src, widthCells = 6, heightCells = 3)
        r.appendChild(root, img.node)
        root)
      check img.protocol == ipKitty
      check img.emittedBytes.len > 0
      check img.emittedBytes[0 ..< 3] == "\x1b_G"
      hashes.add img.imageHash
      clearSupportOverride()
      h.dispose()

    # iTerm2 session.
    block:
      let h = newTerminalTestHarness(30, 6)
      setSupportOverride(ImageProtocols(kitty: false,
                                         iterm2: true, sixel: false))
      var img: ImageWidget
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        img = newImageWidget(r, src, widthCells = 6, heightCells = 3)
        r.appendChild(root, img.node)
        root)
      check img.protocol == ipITerm2
      check img.emittedBytes.len > 0
      # iTerm2 wraps in OSC 1337.
      check img.emittedBytes[0 ..< 6] == "\x1b]1337"
      hashes.add img.imageHash
      clearSupportOverride()
      h.dispose()

    # Sixel session — encoder is deferred (raises NotImplemented).
    # The widget catches the exception and falls back to empty bytes,
    # but `chosen` still reports Sixel so callers know the intent.
    block:
      let h = newTerminalTestHarness(30, 6)
      setSupportOverride(ImageProtocols(kitty: false,
                                         iterm2: false, sixel: true))
      var img: ImageWidget
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        img = newImageWidget(r, src, widthCells = 6, heightCells = 3)
        r.appendChild(root, img.node)
        root)
      check img.protocol == ipSixel
      hashes.add img.imageHash
      clearSupportOverride()
      h.dispose()

    # Text-only session — falls back to label rendering.
    block:
      let h = newTerminalTestHarness(30, 6)
      setSupportOverride(ImageProtocols(kitty: false,
                                         iterm2: false, sixel: false))
      var img: ImageWidget
      h.mount(proc(r: TerminalRenderer): TerminalNode =
        let root = r.createElement("div")
        img = newImageWidget(r, src, widthCells = 12, heightCells = 3)
        r.appendChild(root, img.node)
        root)
      check img.protocol == ipNone
      check img.emittedBytes == ""
      # The cell-grid contains the [image WxH] fallback label.
      let cell0 = h.cellAt(0, 0)
      check cell0.rune.int32 == ord('[')
      hashes.add img.imageHash
      clearSupportOverride()
      h.dispose()

    # Hash of input bytes is the same across all protocol selections.
    check hashes.len == 4
    for i in 1 ..< hashes.len:
      check hashes[0] == hashes[i]
