## test_layout_engine_shared_with_cocoa
##
## A node tree built via isonim-tui, then re-routed through a separate
## (independent) LayoutEngine instance, yields the same Yoga-computed
## dimensions. Verifies `LayoutEngine` is genuinely renderer-agnostic.
##
## *Deferral note*: `isonim-cocoa` requires the Apple Objective-C
## runtime and UIKit — it is not buildable on Linux. We *can* still
## verify the renderer-agnostic property: build two LayoutEngine
## trees (one through TerminalLayout, one independently) with the
## same shape and styles, calculate, and assert identical dimensions.
## The test file's intent is to detect drift in the shared engine.
##
## When isonim-cocoa lands a Linux build (or this test runs on macOS
## CI) the second branch can route through `UIKitRenderer.engine`
## directly. The assertions are identical either way.

import unittest

import isonim_tui
import isonim/layout/layout_engine
import isonim/layout/yoga_bindings

suite "M3: layout engine shared with cocoa":
  test "test_layout_engine_shared_with_cocoa":
    # ---------- Path A: isonim-tui's TerminalLayout ----------
    let tuiLayout = newTerminalLayout(120, 40)
    discard tuiLayout.engine.registerNode(1)
    discard tuiLayout.engine.registerNode(2)
    discard tuiLayout.engine.registerNode(3)
    tuiLayout.engine.addChild(1, 2)
    tuiLayout.engine.addChild(1, 3)

    let rA = tuiLayout.engine.nodes[0].yogaNode
    YGNodeStyleSetWidth(rA, 120.0.cfloat)
    YGNodeStyleSetHeight(rA, 40.0.cfloat)
    YGNodeStyleSetFlexDirection(rA, YGFlexDirection.Row)
    let cA1 = tuiLayout.engine.nodes[1].yogaNode
    YGNodeStyleSetFlexGrow(cA1, 1.0.cfloat)
    YGNodeStyleSetHeight(cA1, 40.0.cfloat)
    let cA2 = tuiLayout.engine.nodes[2].yogaNode
    YGNodeStyleSetFlexGrow(cA2, 2.0.cfloat)
    YGNodeStyleSetHeight(cA2, 40.0.cfloat)

    tuiLayout.calculateLayoutInCells()

    let layoutsA = tuiLayout.engine.allLayouts()

    # ---------- Path B: an independent LayoutEngine ----------
    # Stand-in for the cocoa renderer's engine. Same calls; on macOS
    # this would be `UIKitRenderer.engine`. The LayoutEngine itself
    # does not depend on any renderer.
    let cocoaEngine = newLayoutEngine()
    discard cocoaEngine.registerNode(11)
    discard cocoaEngine.registerNode(12)
    discard cocoaEngine.registerNode(13)
    cocoaEngine.addChild(11, 12)
    cocoaEngine.addChild(11, 13)

    let rB = cocoaEngine.nodes[0].yogaNode
    YGNodeStyleSetWidth(rB, 120.0.cfloat)
    YGNodeStyleSetHeight(rB, 40.0.cfloat)
    YGNodeStyleSetFlexDirection(rB, YGFlexDirection.Row)
    let cB1 = cocoaEngine.nodes[1].yogaNode
    YGNodeStyleSetFlexGrow(cB1, 1.0.cfloat)
    YGNodeStyleSetHeight(cB1, 40.0.cfloat)
    let cB2 = cocoaEngine.nodes[2].yogaNode
    YGNodeStyleSetFlexGrow(cB2, 2.0.cfloat)
    YGNodeStyleSetHeight(cB2, 40.0.cfloat)

    cocoaEngine.calculateLayout(120.0, 40.0)
    let layoutsB = cocoaEngine.allLayouts()

    # ---------- Assert: same Yoga-computed dimensions ----------
    check layoutsA.len == layoutsB.len
    for i in 0 ..< layoutsA.len:
      let a = layoutsA[i].layout
      let b = layoutsB[i].layout
      check a.x == b.x
      check a.y == b.y
      check a.width == b.width
      check a.height == b.height

    # And specifically, the 1:2 flex ratio should produce 40 / 80.
    check layoutsA[1].layout.width == 40.0
    check layoutsA[2].layout.width == 80.0

    tuiLayout.dispose()
    cocoaEngine.freeAll()
