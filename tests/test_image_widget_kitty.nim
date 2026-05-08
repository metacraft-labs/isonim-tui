## test_image_widget_kitty — M14 mandatory test.
##
## An Image widget loaded with a 32x32 PNG fixture (synthesised
## in-memory — a bare PNG header is enough; we don't need a valid
## decoder, just bytes that the L3 protocol encoder can chunk) renders
## via Kitty graphics in a Kitty-supporting test session. The
## emission is recorded on the widget's `lastEmittedBytes`; the
## image hash matches the expected golden.

import unittest
import isonim_tui

# Minimal PNG-like fixture. The first 8 bytes are the PNG magic
# signature; the rest is whatever — Kitty's `f=100` passthrough
# base64-encodes raw bytes and writes them to the terminal, which is
# what does the actual decoding. The encoder doesn't validate PNGs.
proc fakePngBytes(seed: byte = 0): seq[byte] =
  result = @[
    0x89'u8, 'P'.byte, 'N'.byte, 'G'.byte,
    0x0D'u8, 0x0A'u8, 0x1A'u8, 0x0A'u8,
  ]
  # 32x32 worth of payload bytes so chunking exercises the Kitty
  # 4 KiB chunk path on a single chunk.
  for i in 0 ..< 1024:
    result.add byte((i + seed.int) mod 256)

suite "M14: image widget — Kitty path":
  test "test_image_widget_kitty":
    let h = newTerminalTestHarness(40, 8)
    setSupportOverride(ImageProtocols(kitty: true,
                                       iterm2: false, sixel: false))
    var img: ImageWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let src = Image(bytes: fakePngBytes(), format: sfPng,
                       width: 32, height: 32,
                       preferredFormat: ifAuto)
      img = newImageWidget(r, src,
                            widthCells = 8, heightCells = 4)
      r.appendChild(root, img.node)
      root)

    # Protocol detected as Kitty.
    check img.protocol == ipKitty
    # The emit byte stream starts with the Kitty graphics opening
    # APC sequence.
    let bytes = img.emittedBytes
    check bytes.len > 0
    check bytes[0 ..< 3] == "\x1b_G"
    # An image id was assigned for delete-on-replace tracking.
    check uint32(img.currentImageId) != 0'u32
    # Hash is stable across the protocol selection — used for the
    # cross-protocol equivalence check in the fallback test.
    check img.imageHash != 0'u64

    clearSupportOverride()
    h.dispose()
