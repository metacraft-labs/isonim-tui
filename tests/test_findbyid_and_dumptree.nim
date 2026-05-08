## test_findById_and_dumpTree
##
## A tree with several ids returns the matching node from `findById`;
## `dumpTree()` contains every visible node tagged with its id, classes,
## and layout region.

import unittest
import std/[tables, strutils]
import isonim_tui

suite "M2: findById + dumpTree":
  test "test_findById_and_dumpTree":
    let h = newTerminalTestHarness(40, 5)
    h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      r.setAttribute(root, "id", "root")
      r.setAttribute(root, "class", "container outer")

      let header = r.createElement("h1")
      r.setAttribute(header, "id", "title")
      r.setAttribute(header, "class", "heading")
      r.appendChild(header, r.createTextNode("Title"))
      r.appendChild(root, header)

      let content = r.createElement("div")
      r.setAttribute(content, "id", "content")
      r.setAttribute(content, "class", "body")
      r.appendChild(content, r.createTextNode("Body text"))
      r.appendChild(root, content)
      root)

    # findById returns the right nodes.
    let rootNode = h.findById("root")
    check rootNode != nil
    check rootNode.tag == "div"

    let titleNode = h.findById("title")
    check titleNode != nil
    check titleNode.tag == "h1"

    check h.findById("content") != nil
    check h.findById("nonexistent") == nil

    # findByClass.
    let outers = h.findByClass("outer")
    check outers.len == 1
    check outers[0].id == rootNode.id

    let containers = h.findByClass("container")
    check containers.len == 1

    let bodies = h.findByClass("body")
    check bodies.len == 1

    # findByTag.
    let h1s = h.findByTag("h1")
    check h1s.len == 1
    check h1s[0].id == titleNode.id

    # findAll predicate.
    let allNodes = h.findAll(proc(n: TerminalNode): bool =
                              n.attributes.hasKey("id"))
    check allNodes.len == 3

    # dumpTree contains every id and class.
    let dump = h.dumpTree()
    check strutils.contains(dump, "#root")
    check strutils.contains(dump, "#title")
    check strutils.contains(dump, "#content")
    check strutils.contains(dump, ".container")
    check strutils.contains(dump, ".outer")
    check strutils.contains(dump, ".heading")
    check strutils.contains(dump, ".body")
    # Layout region info.
    check strutils.contains(dump, "[")  # `[row,col WxH]`

    # Tree relationship queries.
    check h.parentOf(titleNode).id == rootNode.id
    let kids = h.childrenOf(rootNode)
    check kids.len == 2
    let descs = h.descendantsOf(rootNode)
    # 2 element children + 2 text grandchildren = 4
    check descs.len == 4
    let ancs = h.ancestorsOf(titleNode)
    check ancs.len == 1
    check ancs[0].id == rootNode.id

    h.dispose()
