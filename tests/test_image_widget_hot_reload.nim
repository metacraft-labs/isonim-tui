## test_image_widget_hot_reload — M14 mandatory test.
##
## Image.src mutates from fixture A to fixture B; widget calls
## `L3.deleteImage(oldId)` then emits B. The new image id differs
## from the old; the delete sequence references the old id; the
## emitted bytes change.

import unittest
import std/strutils
import isonim_tui

proc pngFixture(seed: byte): seq[byte] =
  result = @[0x89'u8, 'P'.byte, 'N'.byte, 'G'.byte,
             0x0D'u8, 0x0A'u8, 0x1A'u8, 0x0A'u8]
  for i in 0 ..< 64:
    result.add byte((i + seed.int) mod 256)

suite "M14: image widget — hot reload":
  test "test_image_widget_hot_reload":
    let h = newTerminalTestHarness(30, 6)
    setSupportOverride(ImageProtocols(kitty: true,
                                       iterm2: false, sixel: false))
    var img: ImageWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      let srcA = Image(bytes: pngFixture(1), format: sfPng,
                        width: 16, height: 16,
                        preferredFormat: ifAuto)
      img = newImageWidget(r, srcA, widthCells = 6, heightCells = 3)
      r.appendChild(root, img.node)
      root)

    let firstId = img.currentImageId
    let firstBytes = img.emittedBytes
    let firstHash = img.imageHash
    check firstBytes.len > 0
    check uint32(firstId) != 0'u32

    # Hot-reload: switch to fixture B.
    let srcB = Image(bytes: pngFixture(99), format: sfPng,
                      width: 16, height: 16,
                      preferredFormat: ifAuto)
    img.setSrc(srcB)

    let secondId = img.currentImageId
    let secondBytes = img.emittedBytes
    let secondHash = img.imageHash

    # Second emission used a fresh image id (Kitty path).
    check uint32(secondId) != uint32(firstId)
    # The delete-by-id sequence carries the *old* id so the terminal
    # can free the old payload.
    check img.deleteBytes.len > 0
    check img.deleteBytes.contains("a=d,i=" & $uint32(firstId))
    # The new emit bytes differ from the first.
    check secondBytes != firstBytes
    # Different source bytes → different hashes.
    check secondHash != firstHash

    clearSupportOverride()
    h.dispose()

  test "image_hot_reload_iterm2_no_delete":
    ## iTerm2 has no per-image registry, so hot-reload doesn't emit a
    ## delete sequence — `deleteBytes` stays empty.
    let h = newTerminalTestHarness(30, 6)
    setSupportOverride(ImageProtocols(kitty: false,
                                       iterm2: true, sixel: false))
    var img: ImageWidget
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      img = newImageWidget(r,
        Image(bytes: pngFixture(7), format: sfPng,
              width: 16, height: 16, preferredFormat: ifAuto),
        widthCells = 6, heightCells = 3)
      r.appendChild(root, img.node)
      root)
    check img.protocol == ipITerm2
    check img.deleteBytes == ""
    img.setSrc(Image(bytes: pngFixture(8), format: sfPng,
                     width: 16, height: 16, preferredFormat: ifAuto))
    check img.deleteBytes == ""
    clearSupportOverride()
    h.dispose()
